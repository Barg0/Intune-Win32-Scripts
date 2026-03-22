# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date


# ---------------------------[ Configuration ]---------------------------
# Language this uninstall script is responsible for
$languageCode       = "nl-NL"

# Whether to actually uninstall the language pack from Windows
# (set to $false if you only want to revert to the original language, not remove the pack)
$removeLanguagePack = $true


# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Windows Language Pack $($languageCode)"
$logFileName = "uninstall.log"


# ---------------------------[ Logging Setup ]---------------------------
# Logging configuration
$log           = $true
$logDebug      = $false    # verbose internal debugging
$logGet        = $true     # show [Get] logs
$logRun        = $true     # show [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
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

    # Per-tag toggles
    if ($Tag -eq "Debug" -and -not $logDebug) { return }
    if ($Tag -eq "Get"   -and -not $logGet)   { return }
    if ($Tag -eq "Run"   -and -not $logRun)   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
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
    $duration = $scriptEndTime - $scriptStartTime

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
        $sid = $identity.User.Value
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
        $props = Get-ItemProperty -Path $intlPath -ErrorAction Stop
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
        $props = Get-ItemProperty -Path $kbdPath -ErrorAction Stop
        $layout = $props."1"
        if ($layout) {
            $script:systemKeyboardLayout = "$layout"
            Write-Log "Detected SYSTEM keyboard layout: $layout" -Tag "Info"
        } else {
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


# ---------------------------[ Helper: Get Original Baseline Language ]---------------------------
function Get-OriginalBaselineLanguage {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $systemOriginalPath)) {
        Write-Log "Original baseline not found at $systemOriginalPath" -Tag "Error"
        return $null
    }

    try {
        $props = Get-ItemProperty -Path $systemOriginalPath -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to read Original baseline at $($systemOriginalPath): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        return $null
    }

    $sysLocale = $props.SystemLocale
    $culture   = $props.Culture
    $uiLang    = $props.UILanguage

    if ($sysLocale) {
        Write-Log "Original baseline SystemLocale: '$sysLocale'" -Tag "Debug"
        return "$sysLocale"
    }
    elseif ($culture) {
        Write-Log "Original baseline Culture: '$culture'" -Tag "Debug"
        return "$culture"
    }
    elseif ($uiLang) {
        Write-Log "Original baseline UILanguage: '$uiLang'" -Tag "Debug"
        return "$uiLang"
    }
    else {
        Write-Log "Original baseline has no recognizable language identifier" -Tag "Error"
        return $null
    }
}


# ---------------------------[ Helper: Apply SYSTEM Template to User ]---------------------------
function Set-UserInternationalTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$UserSid
    )

    $intlPath     = "Registry::HKEY_USERS\$UserSid\Control Panel\International"
    $keyboardPath = "Registry::HKEY_USERS\$UserSid\Keyboard Layout\Preload"

    Write-Log "Applying SYSTEM language template to user SID $UserSid" -Tag "Info"

    if (-not (Test-Path -Path $intlPath)) {
        Write-Log "International key not found for SID $UserSid at '$intlPath'. Skipping user configuration" -Tag "Info"
        return
    }

    $template = Get-SystemInternationalTemplate
    if (-not $template -or $template.Keys.Count -eq 0) {
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
    if ($layout) {
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
    } else {
        Write-Log "No SYSTEM keyboard layout detected. Skipping keyboard configuration for SID $UserSid" -Tag "Info"
    }

    Write-Log "International and keyboard template application completed for SID $UserSid" -Tag "Success"
}


# ---------------------------[ Helper: Update User Language List ]---------------------------
function Set-UserLanguageListForSid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$UserSid,
        [Parameter(Mandatory=$true)][string]$TargetLanguage
    )

    Write-Log "Updating user language list for SID $UserSid to '$TargetLanguage'" -Tag "Info"

    $intlUserProfilePath = "Registry::HKEY_USERS\$UserSid\Control Panel\International\User Profile"
    $desktopPath         = "Registry::HKEY_USERS\$UserSid\Control Panel\Desktop"

    try {
        if (-not (Test-Path -Path $intlUserProfilePath)) {
            Write-Log "Creating 'User Profile' key for SID $UserSid at '$intlUserProfilePath'" -Tag "Run"
            New-Item -Path $intlUserProfilePath -Force | Out-Null
            Write-Log "'User Profile' key created for SID $UserSid" -Tag "Debug"
        }

        if (-not (Test-Path -Path $desktopPath)) {
            Write-Log "Creating 'Desktop' key for SID $UserSid at '$desktopPath'" -Tag "Run"
            New-Item -Path $desktopPath -Force | Out-Null
            Write-Log "'Desktop' key created for SID $UserSid" -Tag "Debug"
        }

        $languagesValue = ,$TargetLanguage  # REG_MULTI_SZ expects an array

        Write-Log "Setting 'Languages' (REG_MULTI_SZ) for SID $UserSid to '$TargetLanguage'" -Tag "Run"
        New-ItemProperty -Path $intlUserProfilePath -Name "Languages" -Value $languagesValue -PropertyType MultiString -Force | Out-Null
        Write-Log "'Languages' updated for SID $UserSid" -Tag "Debug"

        Write-Log "Setting 'MUILanguages' (REG_MULTI_SZ) for SID $UserSid to '$TargetLanguage'" -Tag "Run"
        New-ItemProperty -Path $intlUserProfilePath -Name "MUILanguages" -Value $languagesValue -PropertyType MultiString -Force | Out-Null
        Write-Log "'MUILanguages' updated for SID $UserSid" -Tag "Debug"

        Write-Log "Setting 'PreferredUILanguages' (REG_MULTI_SZ) for SID $UserSid to '$TargetLanguage'" -Tag "Run"
        New-ItemProperty -Path $desktopPath -Name "PreferredUILanguages" -Value $languagesValue -PropertyType MultiString -Force | Out-Null
        Write-Log "'PreferredUILanguages' updated for SID $UserSid" -Tag "Debug"

        Write-Log "User language list updated for SID $UserSid to '$TargetLanguage'. Sign-out/reboot may be required for full effect." -Tag "Success"
    }
    catch {
        Write-Log "Failed to update user language list for SID $($UserSid): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }
}

function Set-UserLanguageListForLoadedUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$TargetLanguage
    )

    Write-Log "Updating language list to '$TargetLanguage' for all loaded users" -Tag "Info"
    $userSids = Get-LoadedUserSids

    foreach ($sid in $userSids) {
        Set-UserLanguageListForSid -UserSid $sid -TargetLanguage $TargetLanguage
    }

    Write-Log "Language list update to '$TargetLanguage' completed for all loaded users. A sign-out/reboot may be required." -Tag "Success"
}


# ---------------------------[ Helper: Restore Original System Language ]---------------------------
function Restore-OriginalSystemLanguage {
    [CmdletBinding()]
    param()

    Write-Log "Restoring original system language configuration" -Tag "Info"

    if (-not (Test-Path -Path $systemOriginalPath)) {
        Write-Log "Original baseline at $systemOriginalPath not found. Cannot restore original language." -Tag "Error"
        return
    }

    $originalLanguage = Get-OriginalBaselineLanguage
    if (-not $originalLanguage) {
        Write-Log "Original language could not be determined from baseline. Skipping restore." -Tag "Error"
        return
    }

    Write-Log "Original baseline language resolved as '$originalLanguage'" -Tag "Info"

    try {
        Write-Log "Running Install-Language -Language $originalLanguage -CopyToSettings" -Tag "Run"
        Install-Language -Language $originalLanguage -CopyToSettings -ErrorAction Stop
        Write-Log "Install-Language for original language $originalLanguage with -CopyToSettings completed successfully" -Tag "Success"
    }
    catch {
        Write-Log "Install-Language -Language $($originalLanguage) -CopyToSettings failed: $($_)" -Tag "Error"
        Write-Log "Exception detail (Install-Language original): $($_ | Out-String)" -Tag "Debug"
        # We continue and still try to set locale/culture; worst case they fail too.
    }

    # Read full original baseline for GeoID etc.
    try {
        $props = Get-ItemProperty -Path $systemOriginalPath -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to read original baseline for detailed restore at $($systemOriginalPath): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        $props = $null
    }

    # Set-WinSystemLocale
    try {
        Write-Log "Running Set-WinSystemLocale -SystemLocale $originalLanguage" -Tag "Run"
        Set-WinSystemLocale -SystemLocale $originalLanguage
        Write-Log "Set-WinSystemLocale succeeded for $originalLanguage" -Tag "Success"
        Write-Log "SystemLocale restored to $originalLanguage from original baseline" -Tag "Debug"
    }
    catch {
        Write-Log "Set-WinSystemLocale failed for $($originalLanguage): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # Set-Culture
    try {
        Write-Log "Running Set-Culture -CultureInfo $originalLanguage" -Tag "Run"
        Set-Culture -CultureInfo $originalLanguage
        Write-Log "Set-Culture succeeded for $originalLanguage" -Tag "Success"
        Write-Log "Culture restored to $originalLanguage from original baseline" -Tag "Debug"
    }
    catch {
        Write-Log "Set-Culture failed for $($originalLanguage): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # Set-WinUILanguageOverride
    try {
        Write-Log "Running Set-WinUILanguageOverride -Language $originalLanguage" -Tag "Run"
        Set-WinUILanguageOverride -Language $originalLanguage
        Write-Log "Set-WinUILanguageOverride succeeded for $originalLanguage" -Tag "Success"
        Write-Log "UILanguageOverride restored to $originalLanguage from original baseline" -Tag "Debug"
    }
    catch {
        Write-Log "Set-WinUILanguageOverride failed for $($originalLanguage): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # GeoID / HomeLocation from original baseline if present
    if ($props -and $props.GeoID) {
        try {
            $geoInt = [int]$props.GeoID
            Write-Log "Running Set-WinHomeLocation -GeoId $geoInt (original baseline)" -Tag "Run"
            Set-WinHomeLocation -GeoId $geoInt
            Write-Log "WinHomeLocation set to GeoID $geoInt from original baseline" -Tag "Success"
            Write-Log "GeoID $geoInt successfully applied as WinHomeLocation from original baseline" -Tag "Debug"
        }
        catch {
            Write-Log "Failed to set WinHomeLocation from original baseline GeoID '$($props.GeoID)': $($_)" -Tag "Error"
            Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        }
    }
    else {
        Write-Log "Original baseline has no GeoID. Skipping Set-WinHomeLocation." -Tag "Info"
    }

    # Copy settings to welcome screen / new users
    try {
        Write-Log "Running Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true (original restore)" -Tag "Run"
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-Log "International settings copied to welcome screen and new users (original restore)" -Tag "Success"
        Write-Log "Copy-UserInternationalSettingsToSystem (original restore) completed without errors" -Tag "Debug"
    }
    catch {
        Write-Log "Copy-UserInternationalSettingsToSystem (original restore) failed: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    # Refresh SYSTEM template cache and apply to loaded users
    $script:systemIntlTemplate   = $null
    $script:systemKeyboardLayout = $null

    Write-Log "Refreshing SYSTEM template cache after original language restore" -Tag "Get"
    [void](Get-SystemInternationalTemplate)
    [void](Get-SystemKeyboardLayout)
    Write-Log "SYSTEM template cache refresh completed after original language restore" -Tag "Debug"

    Write-Log "Applying restored original SYSTEM template to all loaded users" -Tag "Info"
    $userSids = Get-LoadedUserSids
    foreach ($sid in $userSids) {
        Set-UserInternationalTemplate -UserSid $sid
    }

    Write-Log "Updating user language list to original language '$originalLanguage' for all loaded users" -Tag "Info"
    Set-UserLanguageListForLoadedUsers -TargetLanguage $originalLanguage

    Write-Log "Original system language restore completed (OS + user context). Sign-out/reboot may be required." -Tag "Success"
}


# ---------------------------[ Helper: Remove IntuneCustomReg if Empty ]---------------------------
function Remove-IntuneCustomRegIfEmpty {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $rootPath)) {
        return
    }

    try {
        $children = Get-ChildItem -Path $rootPath -ErrorAction SilentlyContinue
        $props    = (Get-ItemProperty -Path $rootPath -ErrorAction SilentlyContinue).PSObject.Properties |
                    Where-Object { $_.Name -notlike "PS*" }

        if ((($null -eq $children) -or ($children.Count -eq 0)) -and
            (($null -eq $props)    -or ($props.Count    -eq 0))) {

            Write-Log "IntuneCustomReg root at $rootPath is empty. Removing key." -Tag "Run"
            Remove-Item -Path $rootPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "IntuneCustomReg root removed because it was empty" -Tag "Success"
        }
        else {
            Write-Log "IntuneCustomReg root at $rootPath is not empty. Leaving it in place." -Tag "Debug"
        }
    }
    catch {
        Write-Log "Failed to check or remove IntuneCustomReg root: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }
}


# ---------------------------[ Main Execution ]---------------------------

# If IntuneCustomReg or Original baseline doesn't exist, we can't meaningfully restore
if (-not (Test-Path -Path $rootPath)) {
    Write-Log "IntuneCustomReg root not found at $rootPath. Nothing to uninstall or restore." -Tag "Info"
    Complete-Script -ExitCode 0
}

if (-not (Test-Path -Path $systemOriginalPath)) {
    Write-Log "Original baseline at $systemOriginalPath not found. Cannot restore original language; only cleaning detection marker." -Tag "Error"
}

# Remove detection marker for this language (if Languages key exists)
if (Test-Path -Path $languagesRootPath) {
    Write-Log "Removing detection marker for $languageCode from $languagesRootPath" -Tag "Run"
    try {
        Remove-ItemProperty -Path $languagesRootPath -Name $languageCode -ErrorAction SilentlyContinue
        Write-Log "Detection marker for $languageCode removed (if it existed)" -Tag "Debug"
    }
    catch {
        Write-Log "Failed to remove detection marker for $($languageCode): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }
}
else {
    Write-Log "Languages root not found at $languagesRootPath. No detection marker to remove for $languageCode." -Tag "Info"
}

# Get remaining languages (for cleanup decision only)
$remainingLanguages = @()
if (Test-Path -Path $languagesRootPath) {
    try {
        $langProps = Get-ItemProperty -Path $languagesRootPath -ErrorAction SilentlyContinue
        if ($langProps) {
            $remainingLanguages = $langProps.PSObject.Properties |
                                  Where-Object { $_.Name -notlike "PS*" -and $_.MemberType -eq 'NoteProperty' } |
                                  Select-Object -ExpandProperty Name
        }
    }
    catch {
        Write-Log "Failed to read remaining languages from $($languagesRootPath): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }
}

if ($remainingLanguages.Count -gt 0) {
    Write-Log "Remaining language markers after uninstall of $($languageCode): $($remainingLanguages -join ', ')" -Tag "Info"
} else {
    Write-Log "No remaining language markers after uninstall of $languageCode" -Tag "Info"
}

# Optionally uninstall the language pack itself
if ($removeLanguagePack) {
    try {
        Write-Log "Running Uninstall-Language -Language $languageCode" -Tag "Run"
        Uninstall-Language -Language $languageCode -ErrorAction Stop
        Write-Log "Uninstall-Language succeeded for $languageCode" -Tag "Success"
    }
    catch {
        Write-Log "Uninstall-Language failed for $($languageCode): $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        # Not fatal for original restore – we still try to restore language
    }
}
else {
    Write-Log "removeLanguagePack is set to \$false. Skipping Uninstall-Language for $languageCode." -Tag "Info"
}

# Always attempt to restore the original language
Restore-OriginalSystemLanguage

# If this was the last language marker, clean up LanguageBackup/Languages and possibly IntuneCustomReg root
if ($remainingLanguages.Count -eq 0) {
    Write-Log "No language markers left. Cleaning up LanguageBackup and Languages keys." -Tag "Info"

    try {
        if (Test-Path -Path $languageBackupRootPath) {
            Write-Log "Removing LanguageBackup root at $languageBackupRootPath" -Tag "Run"
            Remove-Item -Path $languageBackupRootPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "LanguageBackup root removed" -Tag "Success"
        }

        if (Test-Path -Path $languagesRootPath) {
            Write-Log "Removing Languages root at $languagesRootPath" -Tag "Run"
            Remove-Item -Path $languagesRootPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Languages root removed" -Tag "Success"
        }
    }
    catch {
        Write-Log "Failed to clean LanguageBackup or Languages keys: $($_)" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    }

    Remove-IntuneCustomRegIfEmpty
}

Write-Log "Language uninstall and original language restore logic completed for $languageCode" -Tag "Success"
Complete-Script -ExitCode 0
