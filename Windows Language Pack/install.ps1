# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date


# ---------------------------[ Configuration ]---------------------------
# Desired language/region to install and configure (e.g. "fr-BE", "de-DE", "nl-NL")
$languageCode  = "nl-NL"

# GeoID for the target region (e.g. 94 = Germany)
# https://learn.microsoft.com/en-us/windows/win32/intl/table-of-geographical-locations
# This is used as a fallback if the SYSTEM International key does not expose a GeoID
$geoId         = 176

# Script version tag for registry bookkeeping
$scriptVersion = "1.0"


# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Windows Language Pack $($languageCode)"
$logFileName = "install.log"


# ---------------------------[ Logging Setup ]---------------------------
# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $true for verbose DEBUG logging
$logGet        = $true    # enable/disable all [Get] logs
$logRun        = $true    # enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}


# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$Message,
        [string]$Tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches
    if (($Tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($Tag -eq "Get")   -and (-not $logGet))   { return }
    if (($Tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    }
    else {
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Get"     { "Blue" }
        "Run"     { "Magenta" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow" }
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}


# ---------------------------[ Exit Function ]---------------------------
function Complete-Script {
    param([int]$ExitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}


# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $scriptName" -Tag "Info"


# ---------------------------[ Constants ]---------------------------
$rootPath               = "HKLM:\SOFTWARE\IntuneCustomReg"
$languageBackupRootPath = Join-Path $rootPath "LanguageBackup"
$systemOriginalPath     = Join-Path $languageBackupRootPath "Original"
$languagesRootPath      = Join-Path $rootPath "Languages"

$script:systemIntlTemplate   = $null
$script:systemKeyboardLayout = $null


# ---------------------------[ System Context Validation ]---------------------------
function Test-IsSystemContext {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $sid      = $identity.User.Value
        Write-Log "Current process SID: $sid" -Tag "Debug"
        return ($sid -eq "S-1-5-18")
    }
    catch {
        Write-Log "Failed to determine SYSTEM context: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        return $false
    }
}

Write-Log "Validating that script is running as SYSTEM" -Tag "Get"
if (-not (Test-IsSystemContext)) {
    Write-Log "Script must run under SYSTEM context" -Tag "Error"
    Complete-Script -ExitCode 1
}


# ---------------------------[ Helper: Get Loaded User SIDs ]---------------------------
function Get-LoadedUserSids {
    [CmdletBinding()]
    param()

    $sids = @()

    Write-Log "Getting loaded user SIDs from HKEY_USERS" -Tag "Get"
    try {
        foreach ($item in Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction Stop) {
            $sid = $item.PSChildName

            # Skip default hive and *_Classes hives
            if ($sid -eq ".DEFAULT") {
                Write-Log "Skipping .DEFAULT hive under HKEY_USERS" -Tag "Debug"
                continue
            }
            if ($sid -like "*_Classes") {
                Write-Log "Skipping SID classes hive '$sid' under HKEY_USERS" -Tag "Debug"
                continue
            }

            # Match classic (S-1-5-21-...) and Entra ID (S-1-12-1-...) user SIDs
            if ($sid -match '^S-1-5-21-' -or $sid -match '^S-1-12-1-') {
                $sids += $sid
                Write-Log "Discovered loaded user SID '$sid'" -Tag "Debug"
            }
            else {
                Write-Log "Skipping well-known / non-user SID '$sid' under HKEY_USERS" -Tag "Debug"
            }
        }

        if ($sids.Count -gt 0) {
            Write-Log "Loaded user SIDs discovered: $($sids -join ', ')" -Tag "Info"
        }
        else {
            Write-Log "No loaded user SIDs found under HKEY_USERS" -Tag "Info"
        }
    }
    catch {
        Write-Log "Failed to enumerate HKEY_USERS: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    return $sids
}


# ---------------------------[ Helper: Get SYSTEM International Template ]---------------------------
function Get-SystemInternationalTemplate {
    [CmdletBinding()]
    param()

    if ($script:systemIntlTemplate) {
        Write-Log "Returning cached SYSTEM International template" -Tag "Debug"
        return $script:systemIntlTemplate
    }

    $intlPath = "HKCU:\Control Panel\International"
    Write-Log "Getting SYSTEM International template from $intlPath" -Tag "Get"

    try {
        $props    = Get-ItemProperty -Path $intlPath -ErrorAction Stop
        $template = @{}

        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -notlike "PS*") {
                $template[$prop.Name] = "$($prop.Value)"
            }
        }

        $script:systemIntlTemplate = $template
        Write-Log "SYSTEM International template contains $($template.Keys.Count) values" -Tag "Info"
        Write-Log "SYSTEM International keys: $($template.Keys -join ', ')" -Tag "Debug"
    }
    catch {
        Write-Log "Failed to read SYSTEM International template: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        $script:systemIntlTemplate = @{}
    }

    return $script:systemIntlTemplate
}


# ---------------------------[ Helper: Get SYSTEM Keyboard Layout ]---------------------------
function Get-SystemKeyboardLayout {
    [CmdletBinding()]
    param()

    if ($script:systemKeyboardLayout) {
        Write-Log "Returning cached SYSTEM keyboard layout '$script:systemKeyboardLayout'" -Tag "Debug"
        return $script:systemKeyboardLayout
    }

    $kbdPath = "HKCU:\Keyboard Layout\Preload"
    Write-Log "Getting SYSTEM keyboard layout from $kbdPath" -Tag "Get"

    try {
        $props  = Get-ItemProperty -Path $kbdPath -ErrorAction Stop
        $layout = $props."1"
        if ($layout) {
            $script:systemKeyboardLayout = "$layout"
            Write-Log "Detected SYSTEM keyboard layout: $layout" -Tag "Info"
        }
        else {
            Write-Log "SYSTEM keyboard layout value '1' is empty" -Tag "Info"
        }
    }
    catch {
        Write-Log "Failed to read SYSTEM keyboard layout from $($kbdPath): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        $script:systemKeyboardLayout = $null
    }

    return $script:systemKeyboardLayout
}


# ---------------------------[ Helper: Save SYSTEM Baseline (Original) ]---------------------------
function Save-SystemOriginalBaseline {
    [CmdletBinding()]
    param()

    if (Test-Path -Path $systemOriginalPath) {
        Write-Log "System original baseline already exists at $systemOriginalPath. Skipping creation" -Tag "Info"
        return
    }

    Write-Log "Creating system original baseline snapshot" -Tag "Run"

    try {
        New-Item -Path $systemOriginalPath -Force | Out-Null
        Write-Log "Created original baseline key at $systemOriginalPath" -Tag "Debug"

        # SystemLocale
        try {
            Write-Log "Getting original SystemLocale" -Tag "Get"
            $systemLocale = (Get-WinSystemLocale).Name
            Write-Log "Original SystemLocale detected: $systemLocale" -Tag "Debug"
        }
        catch {
            Write-Log "Failed to get original SystemLocale: $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
            $systemLocale = $null
        }

        # Culture
        try {
            Write-Log "Getting original Culture" -Tag "Get"
            $systemCulture = (Get-Culture).Name
            Write-Log "Original Culture detected: $systemCulture" -Tag "Debug"
        }
        catch {
            Write-Log "Failed to get original Culture: $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
            $systemCulture = $null
        }

        # UILanguage / UILanguageOverride
        try {
            Write-Log "Getting original UILanguageOverride" -Tag "Get"
            $uiLanguage = Get-WinUILanguageOverride -ErrorAction SilentlyContinue
            if (-not $uiLanguage) {
                $uiLanguage = (Get-Culture).Name
                Write-Log "UILanguageOverride not set. Falling back to Culture '$uiLanguage'" -Tag "Debug"
            }
            else {
                Write-Log "Original UILanguageOverride detected: $uiLanguage" -Tag "Debug"
            }
        }
        catch {
            Write-Log "Failed to get original UILanguageOverride: $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
            $uiLanguage = $null
        }

        if ($null -ne $systemLocale) {
            Write-Log "Saving original SystemLocale '$systemLocale' to baseline" -Tag "Run"
            New-ItemProperty -Path $systemOriginalPath -Name "SystemLocale" -Value $systemLocale -PropertyType String -Force | Out-Null
        }
        if ($null -ne $systemCulture) {
            Write-Log "Saving original Culture '$systemCulture' to baseline" -Tag "Run"
            New-ItemProperty -Path $systemOriginalPath -Name "Culture" -Value $systemCulture -PropertyType String -Force | Out-Null
        }
        if ($null -ne $uiLanguage) {
            Write-Log "Saving original UILanguage '$uiLanguage' to baseline" -Tag "Run"
            New-ItemProperty -Path $systemOriginalPath -Name "UILanguage" -Value $uiLanguage -PropertyType String -Force | Out-Null
        }

        # GeoID (if present)
        try {
            Write-Log "Getting original GeoID from SYSTEM International" -Tag "Get"
            $intlProps = Get-ItemProperty -Path "HKCU:\Control Panel\International" -ErrorAction Stop
            if ($null -ne $intlProps.GeoID) {
                Write-Log "Original GeoID detected: $($intlProps.GeoID)" -Tag "Debug"
                New-ItemProperty -Path $systemOriginalPath -Name "GeoID" -Value "$($intlProps.GeoID)" -PropertyType String -Force | Out-Null
            }
            else {
                Write-Log "GeoID not present in original SYSTEM International" -Tag "Debug"
            }
        }
        catch {
            Write-Log "Failed to read GeoID for original baseline: $($_)" -Tag "Debug"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        }

        # Baseline metadata
        New-ItemProperty -Path $systemOriginalPath -Name "BaselineType"  -Value "Original"     -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $systemOriginalPath -Name "ScriptVersion" -Value $scriptVersion -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $systemOriginalPath -Name "Timestamp"     -Value (Get-Date).ToString("o") -PropertyType String -Force | Out-Null

        Write-Log "System original baseline snapshot created at $systemOriginalPath" -Tag "Success"
        Write-Log "System original baseline creation completed without errors" -Tag "Debug"
    }
    catch {
        Write-Log "Failed to create system original baseline: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }
}


# ---------------------------[ System Language Configuration ]---------------------------
function Set-SystemLanguageConfiguration {
    [CmdletBinding()]
    param()

    Write-Log "Installing and configuring system language $languageCode" -Tag "Info"

    # Install-Language with -CopyToSettings (primary)
    $installSucceeded = $false
    try {
        Write-Log "Running Install-Language -Language $languageCode -CopyToSettings" -Tag "Run"
        Install-Language -Language $languageCode -CopyToSettings -ErrorAction Stop
        Write-Log "Language pack $languageCode installed successfully with -CopyToSettings" -Tag "Success"
        Write-Log "Install-Language for $languageCode with -CopyToSettings completed without errors" -Tag "Debug"
        $installSucceeded = $true
    }
    catch {
        Write-Log "Install-Language -Language $($languageCode) -CopyToSettings failed: $($_)" -Tag "Error"
        Write-Log "Exception detail (primary Install-Language): $($_ | Out-String)" -Tag "Debug"
    }

    # Fallback: Install-Language without -CopyToSettings
    if (-not $installSucceeded) {
        try {
            Write-Log "Falling back to Install-Language -Language $languageCode (without -CopyToSettings)" -Tag "Info"
            Write-Log "Running Install-Language -Language $languageCode" -Tag "Run"
            Install-Language -Language $languageCode -ErrorAction Stop
            Write-Log "Language pack $languageCode installed successfully without -CopyToSettings" -Tag "Success"
            Write-Log "Fallback Install-Language for $languageCode completed without errors" -Tag "Debug"
            $installSucceeded = $true
        }
        catch {
            Write-Log "Fallback Install-Language -Language $($languageCode) (without -CopyToSettings) also failed: $($_)" -Tag "Error"
            Write-Log "Exception detail (fallback Install-Language): $($_ | Out-String)" -Tag "Debug"
            Complete-Script -ExitCode 1
        }
    }

    # Set-WinSystemLocale
    try {
        Write-Log "Running Set-WinSystemLocale -SystemLocale $languageCode" -Tag "Run"
        Set-WinSystemLocale -SystemLocale $languageCode
        Write-Log "Set-WinSystemLocale succeeded for $languageCode" -Tag "Success"
        Write-Log "SystemLocale is now set to $languageCode" -Tag "Debug"
    }
    catch {
        Write-Log "Set-WinSystemLocale failed for $($languageCode): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        Complete-Script -ExitCode 1
    }

    # Set-WinUILanguageOverride
    try {
        Write-Log "Running Set-WinUILanguageOverride -Language $languageCode" -Tag "Run"
        Set-WinUILanguageOverride -Language $languageCode
        Write-Log "Set-WinUILanguageOverride succeeded for $languageCode" -Tag "Success"
        Write-Log "UILanguageOverride is now set to $languageCode" -Tag "Debug"
    }
    catch {
        Write-Log "Set-WinUILanguageOverride failed for $($languageCode): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        Complete-Script -ExitCode 1
    }

    # Set-Culture
    try {
        Write-Log "Running Set-Culture -CultureInfo $languageCode" -Tag "Run"
        Set-Culture -CultureInfo $languageCode
        Write-Log "Set-Culture succeeded for $languageCode" -Tag "Success"
        Write-Log "Culture is now set to $languageCode" -Tag "Debug"
    }
    catch {
        Write-Log "Set-Culture failed for $($languageCode): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        Complete-Script -ExitCode 1
    }

    # Dynamic GeoID with config fallback
    try {
        Write-Log "Getting GeoID from HKCU:\Control Panel\International after language change" -Tag "Get"
        $intlProps   = Get-ItemProperty -Path "HKCU:\Control Panel\International" -ErrorAction Stop
        $geoIdString = $intlProps.GeoID

        $resolvedGeoId = $null

        if ($null -ne $geoIdString) {
            $resolvedGeoId = [int]$geoIdString
            Write-Log "Dynamic GeoID detected from SYSTEM International: $resolvedGeoId" -Tag "Debug"
        }
        else {
            Write-Log "GeoID not present in SYSTEM International. Using GeoID from configuration: $geoId" -Tag "Info"
            $resolvedGeoId = $geoId
        }

        if ($null -ne $resolvedGeoId) {
            Write-Log "Running Set-WinHomeLocation -GeoId $resolvedGeoId" -Tag "Run"
            Set-WinHomeLocation -GeoId $resolvedGeoId
            Write-Log "WinHomeLocation set to GeoID $resolvedGeoId" -Tag "Success"
            Write-Log "GeoID $resolvedGeoId successfully applied as WinHomeLocation" -Tag "Debug"
        }
        else {
            Write-Log "No GeoID could be resolved. WinHomeLocation not changed." -Tag "Info"
        }
    }
    catch {
        Write-Log "Failed to determine or set GeoID / WinHomeLocation: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # Copy settings to welcome screen and new users
    try {
        Write-Log "Running Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true" -Tag "Run"
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-Log "International settings copied to welcome screen and new users" -Tag "Success"
        Write-Log "Copy-UserInternationalSettingsToSystem completed without errors" -Tag "Debug"
    }
    catch {
        Write-Log "Copy-UserInternationalSettingsToSystem failed: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # Refresh template/cache after language change
    $script:systemIntlTemplate   = $null
    $script:systemKeyboardLayout = $null

    Write-Log "Refreshing SYSTEM template cache after language configuration" -Tag "Get"
    [void](Get-SystemInternationalTemplate)
    [void](Get-SystemKeyboardLayout)
    Write-Log "SYSTEM template cache refresh completed" -Tag "Debug"
}


# ---------------------------[ Apply SYSTEM Template to User ]---------------------------
function Set-UserInternationalTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserSid
    )

    $intlPath     = "Registry::HKEY_USERS\$UserSid\Control Panel\International"
    $keyboardPath = "Registry::HKEY_USERS\$UserSid\Keyboard Layout\Preload"

    Write-Log "Applying SYSTEM language template to user SID $UserSid" -Tag "Info"

    if (-not (Test-Path -Path $intlPath)) {
        Write-Log "International key not found for SID $UserSid at '$intlPath'. Skipping user configuration" -Tag "Info"
        return
    }

    $template = Get-SystemInternationalTemplate
    if ((-not $template) -or ($template.Keys.Count -eq 0)) {
        Write-Log "SYSTEM International template is empty. Cannot apply to SID $UserSid" -Tag "Error"
        return
    }

    foreach ($name in $template.Keys) {
        $value = $template[$name]
        try {
            Write-Log "Setting Intl '$name' = '$value' for SID $UserSid" -Tag "Run"
            Set-ItemProperty -Path $intlPath -Name $name -Value $value -Force -ErrorAction Stop
            Write-Log "Intl '$name' applied for SID $UserSid" -Tag "Debug"
        }
        catch {
            Write-Log "Failed to set Intl '$name' for SID $($UserSid): $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        }
    }

    $layout = Get-SystemKeyboardLayout
    if ($null -ne $layout) {
        if (-not (Test-Path -Path $keyboardPath)) {
            Write-Log "Keyboard Layout\Preload key missing for SID $UserSid. Creating it" -Tag "Run"
            New-Item -Path $keyboardPath -Force | Out-Null
            Write-Log "Keyboard Layout\Preload key created for SID $UserSid" -Tag "Debug"
        }
        try {
            Write-Log "Setting keyboard layout '1' = '$layout' for SID $UserSid" -Tag "Run"
            Set-ItemProperty -Path $keyboardPath -Name "1" -Value $layout -Force -ErrorAction Stop
            Write-Log "Keyboard layout '$layout' applied to SID $UserSid" -Tag "Success"
            Write-Log "Keyboard layout '1' for SID $UserSid is now '$layout'" -Tag "Debug"
        }
        catch {
            Write-Log "Failed to apply keyboard layout '$layout' to SID $($UserSid): $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        }
    }
    else {
        Write-Log "No SYSTEM keyboard layout detected. Skipping keyboard configuration for SID $UserSid" -Tag "Info"
    }

    Write-Log "International and keyboard template application completed for SID $UserSid" -Tag "Success"
}


# ---------------------------[ Main Execution ]---------------------------
Write-Log "Ensuring IntuneCustomReg registry structure exists" -Tag "Info"
try {
    if (-not (Test-Path -Path $rootPath)) {
        Write-Log "Creating root registry key at $rootPath" -Tag "Run"
        New-Item -Path $rootPath -Force | Out-Null
        Write-Log "Root registry key at $rootPath created" -Tag "Debug"
    }
    if (-not (Test-Path -Path $languageBackupRootPath)) {
        Write-Log "Creating language backup root at $languageBackupRootPath" -Tag "Run"
        New-Item -Path $languageBackupRootPath -Force | Out-Null
        Write-Log "Language backup root at $languageBackupRootPath created" -Tag "Debug"
    }
    if (-not (Test-Path -Path $languagesRootPath)) {
        Write-Log "Creating languages root at $languagesRootPath" -Tag "Run"
        New-Item -Path $languagesRootPath -Force | Out-Null
        Write-Log "Languages root at $languagesRootPath created" -Tag "Debug"
    }

    Write-Log "IntuneCustomReg registry structure is present" -Tag "Success"
    Write-Log "Registry structure validation and creation completed without errors" -Tag "Debug"
}
catch {
    Write-Log "Failed to create IntuneCustomReg registry structure: $($_)" -Tag "Error"
    Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    Complete-Script -ExitCode 1
}

Write-Log "Capturing original baseline before applying language $languageCode" -Tag "Info"
Save-SystemOriginalBaseline

Write-Log "Configuring system language for $languageCode" -Tag "Info"
Set-SystemLanguageConfiguration

Write-Log "Applying SYSTEM template to all loaded users" -Tag "Info"
$userSids = Get-LoadedUserSids
foreach ($sid in $userSids) {
    Set-UserInternationalTemplate -UserSid $sid
}

try {
    Write-Log "Writing detection marker for $languageCode under $languagesRootPath" -Tag "Run"
    New-ItemProperty -Path $languagesRootPath -Name $languageCode -Value "true" -PropertyType String -Force | Out-Null
    Write-Log "Detection marker for $languageCode written to $languagesRootPath" -Tag "Debug"

    Write-Log "Writing language backup metadata under $languageBackupRootPath" -Tag "Run"
    New-ItemProperty -Path $languageBackupRootPath -Name "LastInstalledLanguage"      -Value $languageCode  -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $languageBackupRootPath -Name "LastInstalledScriptVersion" -Value $scriptVersion -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $languageBackupRootPath -Name "LastInstallTimestamp"       -Value (Get-Date).ToString("o") -PropertyType String -Force | Out-Null
    Write-Log "Language backup metadata for $languageCode written under $languageBackupRootPath" -Tag "Debug"

    Write-Log "Detection marker and language backup metadata written for $languageCode" -Tag "Success"
}
catch {
    Write-Log "Failed to set detection marker or metadata: $($_)" -Tag "Error"
    Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    Complete-Script -ExitCode 1
}

Write-Log "Language installation and configuration completed for $languageCode" -Tag "Success"
Complete-Script -ExitCode 0
