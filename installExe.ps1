# ---------------------------[ Script Start Timestamp ]--------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Configuration ]------------------------------
$applicationName       = "__REGISTRY_DISPLAY_NAME__"
$installerName         = "setup.exe"
$installerArgumentsExe = '/silent'   # Or "" for no args (when installer reads silent config from .ini in same folder)

# Shortcut configuration (set $createShortcuts = $true to enable)
$createShortcuts   = $false
$desktopShortcuts  = @(
    # @{ Name = "My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
$startMenuShortcuts = @(
    # @{ Name = "MyApp\My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
    # @{ Name = "MyApp\My Application Help"; TargetPath = "$env:ProgramFiles\MyApp\help.exe"; WorkingDirectory = "$env:ProgramFiles\MyApp" }
)

# ---------------------------[ UNC Path & Authentication ]---------------------
# Optional: Use when installer is on a network share (Entra-joined devices need creds)
$installerPathOverride = ""   # UNC root only, e.g. "\\server01.domain.tld\software"
$useUncAuth           = $false
$uncCredential        = $null   # [PSCredential] when $useUncAuth = $true: [PSCredential]::new("user@domain.tld", (ConvertTo-SecureString "password" -AsPlainText -Force))

# ---------------------------[ Paths (computed) ]--------
if (-not [string]::IsNullOrWhiteSpace($installerPathOverride)) {
    $installerPath = Join-Path -Path $installerPathOverride.TrimEnd('\') -ChildPath $installerName
} else {
    $installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName
}

# ---------------------------[ Registry Configuration ]--------------------------
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) { $applicationName -replace '[\*\?\[\]]', '' } else {
    $applicationName
}

# ---------------------------[ Logging Configuration ]--------------------------
$scriptName       = $applicationNameClean
$logFileName      = "install.log"
$log              = $true
$logDebug         = $false
$logGet           = $true
$logRun           = $true
$enableLogFile    = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    try {
        $null = New-Item -ItemType Directory -Path $logFileDirectory -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to create log directory '$logFileDirectory': $($_.Exception.Message)"
    }
}

# ---------------------------[ Logging Function ]------------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )
    if (-not $log) { return }
    if (($tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($tag -eq "Get")   -and (-not $logGet))   { return }
    if (($tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $tag.Trim()
    if ($tagList -contains $rawTag) { $rawTag = $rawTag.PadRight(7) }
    else { $rawTag = "Error  " }

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

    $logMessage = "$timestamp [  $rawTag ] $message"
    if ($enableLogFile) {
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ---------------------------[ Exit Function ]-------------------------------
function Complete-Script {
    [CmdletBinding()]
    param([int]$exitCode)
    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $exitCode
}

# ---------------------------[ UNC Path Access Function ]-----------------------
function Test-UncPathAccess {
    [CmdletBinding()]
    param(
        [string]$path,
        [bool]$useUncAuth,
        [PSCredential]$uncCredential
    )
    if (-not $path.StartsWith("\\")) { return $true }
    if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Write-Log "UNC path accessible without credentials." -Tag "Success"
        return $true
    }
    if (-not $useUncAuth -or -not $uncCredential) {
        Write-Log "UNC path not accessible. Set `$useUncAuth = `$true and provide `$uncCredential (PSCredential) for Entra-joined devices." -Tag "Error"
        return $false
    }
    $parts = $path.TrimStart('\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) {
        Write-Log "Invalid UNC path: cannot extract share root." -Tag "Error"
        return $false
    }
    $shareRoot = "\\$($parts[0])\$($parts[1])"
    Write-Log "Establishing UNC credentials for share: ${shareRoot}" -Tag "Get"
    try {
        $credUser = $uncCredential.UserName
        $credPass = $uncCredential.GetNetworkCredential().Password
        $netUseResult = net use $shareRoot /user:$credUser $credPass 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "net use failed: $netUseResult" -Tag "Error"
            return $false
        }
        if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
            Write-Log "UNC path accessible after authentication." -Tag "Success"
            return $true
        }
        Write-Log "UNC path still not accessible after authentication." -Tag "Error"
        return $false
    }
    catch {
        Write-Log "UNC authentication failed: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

# ---------------------------[ Pending Reboot Check Function ]------------------
function Test-PendingReboot {
    [CmdletBinding()]
    param()

    $rebootPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'
    )

    foreach ($path in $rebootPaths) {
        if (Test-Path -Path $path) { return $true }
    }

    $sessionManagerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    if (Test-Path -Path $sessionManagerPath) {
        $value = Get-ItemProperty -Path $sessionManagerPath -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($value -and $value.PendingFileRenameOperations) { return $true }
        $value2 = Get-ItemProperty -Path $sessionManagerPath -Name 'PendingFileRenameOperations2' -ErrorAction SilentlyContinue
        if ($value2 -and $value2.PendingFileRenameOperations2) { return $true }
    }

    $updateExePath = 'HKLM:\SOFTWARE\Microsoft\Updates'
    if (Test-Path -Path $updateExePath) {
        $volatile = Get-ItemProperty -Path $updateExePath -Name 'UpdateExeVolatile' -ErrorAction SilentlyContinue
        if ($volatile -and $volatile.UpdateExeVolatile -ne 0) { return $true }
    }

    return $false
}

# ---------------------------[ Installer Exit Code Meaning Function ]-----------
function Get-InstallerExitCodeMeaning {
    [CmdletBinding()]
    param([int]$exitCode)

    $exitCodeMap = @{
        0     = 'Success'
        13    = 'Invalid data'
        87    = 'Invalid parameter'
        120   = 'Call not implemented (custom action restriction)'
        1259  = 'App incompatibility - user chose not to install'
        1601  = 'Windows Installer service not accessible'
        1602  = 'User canceled installation'
        1603  = 'Fatal error during installation'
        1604  = 'Installation suspended, incomplete'
        1605  = 'Unknown product (valid only for installed products)'
        1606  = 'Unknown feature identifier'
        1607  = 'Unknown component identifier'
        1608  = 'Unknown property'
        1609  = 'Invalid handle state'
        1610  = 'Configuration data corrupt'
        1611  = 'Component qualifier not present'
        1612  = 'Installation source not available'
        1613  = 'Windows Installer service needs update'
        1614  = 'Product is uninstalled'
        1615  = 'Invalid or unsupported SQL query syntax'
        1616  = 'Record field does not exist'
        1618  = 'Another installation already in progress'
        1619  = 'Installation package could not be opened'
        1620  = 'Installation package invalid'
        1621  = 'Windows Installer UI startup error'
        1622  = 'Installation log file error'
        1623  = 'Installation package language not supported'
        1624  = 'Error applying transforms'
        1625  = 'Installation forbidden by system policy'
        1626  = 'Function could not be executed'
        1627  = 'Function failed during execution'
        1628  = 'Invalid or unknown table specified'
        1629  = 'Data type mismatch'
        1630  = 'Unsupported data type'
        1631  = 'Windows Installer service failed to start'
        1632  = 'Temp folder full or inaccessible'
        1633  = 'Installation package not supported on this platform'
        1634  = 'Component not used on this machine'
        1635  = 'Patch package could not be opened'
        1636  = 'Patch package invalid'
        1637  = 'Patch package requires newer Windows Installer'
        1638  = 'Another version already installed'
        1639  = 'Invalid command line argument'
        1640  = 'Installation not permitted from Terminal Server session'
        1641  = 'Success - installer initiated restart'
        1642  = 'Patch target not found (upgrade patch)'
        1643  = 'Patch package forbidden by policy'
        1644  = 'Customizations forbidden by policy'
        1645  = 'Installation from Remote Desktop prohibited'
        1646  = 'Patch removal not supported'
        1647  = 'Patch not applied to this product'
        1648  = 'No valid patch sequence found'
        1649  = 'Patch removal disallowed by policy'
        1650  = 'Invalid XML patch data'
        1651  = 'Patch failed for advertised product'
        1652  = 'Windows Installer not accessible in Safe Mode'
        1653  = 'Rollback disabled - multiple-package transaction'
        1654  = 'Installation rejected (e.g. ARM - unsigned package)'
        3010  = 'Success - restart required to complete installation'
    }

    if ($exitCodeMap.ContainsKey($exitCode)) {
        return $exitCodeMap[$exitCode]
    }
    return "Unknown exit code (vendor-specific or generic failure)"
}

# ---------------------------[ Execute Install Process Function ]---------------
function Invoke-InstallProcess {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [string]$context = "Install"
    )
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        Write-Log "FilePath is empty or null. Cannot start $context process." -Tag "Error"
        return $null
    }
    Write-Log "Starting $context process: '$filePath' $argumentList" -Tag "Run"
    try {
        $processParams = @{ FilePath = $filePath; Wait = $true; PassThru = $true; NoNewWindow = $true }
        if (-not [string]::IsNullOrWhiteSpace($argumentList)) { $processParams['ArgumentList'] = $argumentList }
        $process = Start-Process @processParams
        if ($null -eq $process) {
            Write-Log "Start-Process did not return a process object. $context result unknown." -Tag "Error"
            return $null
        }
    }
    catch {
        Write-Log "$context process failed to start: $($_.Exception.Message)" -Tag "Error"
        Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        return $null
    }
    Write-Log "$context process ID: $($process.Id)" -Tag "Debug"
    Write-Log "$context exit code: $($process.ExitCode)" -Tag "Info"
    return $process
}

# ---------------------------[ Installation Verification Function ]--------------
function Test-InstallationVerification {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [int]$maxRetries = 3,
        [int]$retryDelay = 5,
        [bool]$useWildcardMatching = $false
    )
    Write-Log "Waiting for registry keys to be populated..." -Tag "Info"
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "Retry attempt $attempt of $maxRetries after $retryDelay seconds..." -Tag "Info"
            Start-Sleep -Seconds $retryDelay
        }
        try {
            $applicationFound = Test-ApplicationInstalled -applicationName $applicationName -registryPaths $registryPaths -useWildcardMatching $useWildcardMatching
            if ($applicationFound) {
                Write-Log "$applicationName is installed and verified in registry." -Tag "Success"
                return $true
            }
        }
        catch {
            Write-Log "Exception during verification attempt $attempt : $($_.Exception.Message)" -Tag "Error"
            Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        }
    }
    Write-Log "$applicationName was not found in registry after $maxRetries attempts. Installation may have failed." -Tag "Error"
    return $false
}

# ---------------------------[ Detection Function ]----------------------------
function Test-ApplicationInstalled {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [bool]$useWildcardMatching = $false
    )
    if ($useWildcardMatching) {
        Write-Log "Checking registry for application '$applicationName' (wildcard matching enabled)." -Tag "Get"
    } else {
        Write-Log "Checking registry for application '$applicationName'." -Tag "Get"
    }
    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Registry path '$registryPath' does not exist, skipping." -Tag "Debug"
            continue
        }
        Write-Log "Searching in registry path: $registryPath" -Tag "Get"
        $subKeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subKeys -or $subKeys.Count -eq 0) {
            Write-Log "No subkeys found under: $registryPath" -Tag "Debug"
            continue
        }
        Write-Log "Found $($subKeys.Count) subkeys under: $registryPath" -Tag "Debug"
        foreach ($subKey in $subKeys) {
            $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }
            $displayName = $properties.DisplayName
            if ($displayName) { Write-Log "Found product: '$displayName'" -Tag "Debug" }
            $isMatch = if ($useWildcardMatching) { $displayName -like $applicationName } else { $displayName -eq $applicationName }
            if ($isMatch) {
                Write-Log "Match found for application: '$displayName'" -Tag "Success"
                return $true
            }
        }
    }
    return $false
}

# ---------------------------[ Shortcut Creation Function ]---------------------
function Invoke-ShortcutCreation {
    [CmdletBinding()]
    param(
        [array]$shortcuts,
        [string]$baseFolder,
        [string]$locationName
    )

    if ($null -eq $shortcuts -or $shortcuts.Count -eq 0) { return }

    if (-not (Test-Path -Path $baseFolder)) {
        Write-Log "Shortcut folder does not exist, skipping ${$locationName}: $baseFolder" -Tag "Debug"
        return
    }

    foreach ($entry in $shortcuts) {
        $name = $entry.Name
        $targetPath = [System.Environment]::ExpandEnvironmentVariables($entry.TargetPath)

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($targetPath)) {
            Write-Log "Shortcut entry missing Name or TargetPath, skipping." -Tag "Debug"
            continue
        }

        $shortcutName = $name
        $destinationFolder = $baseFolder
        if ($name -match '\\') {
            $lastSep = $name.LastIndexOf('\')
            $subfolder = $name.Substring(0, $lastSep)
            $shortcutName = $name.Substring($lastSep + 1)
            $destinationFolder = Join-Path -Path $baseFolder -ChildPath $subfolder
        }

        $shortcutPath = Join-Path -Path $destinationFolder -ChildPath "$shortcutName.lnk"

        if (-not (Test-Path -Path $targetPath)) {
            Write-Log "Target not found, skipping shortcut '$name' -> '$targetPath'" -Tag "Info"
            continue
        }

        if (Test-Path -Path $shortcutPath) {
            Write-Log "Shortcut already exists: $locationName\$name.lnk" -Tag "Success"
            continue
        }

        try {
            if (-not (Test-Path -Path $destinationFolder)) {
                $null = New-Item -ItemType Directory -Path $destinationFolder -Force -ErrorAction Stop
            }
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $targetPath
            if ($entry.Arguments) { $shortcut.Arguments = $entry.Arguments }
            if ($entry.WorkingDirectory) { $shortcut.WorkingDirectory = [System.Environment]::ExpandEnvironmentVariables($entry.WorkingDirectory) }
            $shortcut.Save()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
            Write-Log "Created shortcut: $locationName\$name.lnk -> $targetPath" -Tag "Success"
        }
        catch {
            Write-Log "Failed to create shortcut '$name': $($_.Exception.Message)" -Tag "Error"
            Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        }
    }
}

# ---------------------------[ Script Start ]--------------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

# ---------------------------[ Installer Detection ]------------------------------
Write-Log "Validating installer path..." -Tag "Get"

if (-not (Test-UncPathAccess -path $installerPath -useUncAuth $useUncAuth -uncCredential $uncCredential)) {
    Complete-Script -exitCode 1
}

if (-not (Test-Path -Path $installerPath)) {
    Write-Log "Installer not found at path: $installerPath" -Tag "Error"
    Complete-Script -exitCode 1
}

Write-Log "Installer found at path: $installerPath" -Tag "Success"

# ---------------------------[ Pending Reboot Check ]--------------------------
Write-Log "Checking for pending system reboot..." -Tag "Get"
$pendingReboot = Test-PendingReboot
if ($pendingReboot) {
    Write-Log "Pending reboot detected. Installation will proceed anyway. Intune can handle soft reboot after exit." -Tag "Info"
}
else {
    Write-Log "No pending reboot detected." -Tag "Success"
}

# ---------------------------[ Install ]-------------------------------------
Write-Log "Starting installation for '$applicationName'." -Tag "Run"

$processExitCode = $null

try {
    $installParams = @{ filePath = $installerPath; context = "EXE installation" }
    if (-not [string]::IsNullOrWhiteSpace($installerArgumentsExe)) {
        $installParams['argumentList'] = $installerArgumentsExe
    }
    $process = Invoke-InstallProcess @installParams

    if ($null -ne $process) {
        $processExitCode = $process.ExitCode
        $exitMeaning = Get-InstallerExitCodeMeaning -exitCode $process.ExitCode

        Write-Log "EXE installer exit code: $($process.ExitCode) - $exitMeaning" -Tag "Info"

        if ($process.ExitCode -eq 0) {
            Write-Log "EXE installation completed successfully." -Tag "Success"
        }
        elseif ($process.ExitCode -eq 3010 -or $process.ExitCode -eq 1641) {
            Write-Log "EXE installation completed successfully. Reboot required (exit code $($process.ExitCode)). Intune will handle soft reboot." -Tag "Info"
        }
        elseif ($process.ExitCode -eq 1602) {
            Write-Log "Installation was canceled by user." -Tag "Info"
        }
        else {
            Write-Log "EXE installation returned exit code $($process.ExitCode): $exitMeaning" -Tag "Info"
        }
    }
    else {
        Write-Log "Process object was null. Using exit code 1 for verification. Continuing to registry check..." -Tag "Info"
        $processExitCode = 1
    }

    Write-Log "EXE installer process has completed. Verifying installation via registry detection..." -Tag "Info"
}
catch {
    Write-Log "Exception during installation: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
    Complete-Script -exitCode 1
}

# ---------------------------[ Installation Verification ]----------------------
$verificationParams = @{
    applicationName       = $applicationName
    registryPaths         = $registrySearchPaths
    useWildcardMatching   = $useWildcardMatching
}
$verificationSuccess = Test-InstallationVerification @verificationParams

if ($verificationSuccess) {
    if ($createShortcuts) {
        Write-Log "Shortcut creation enabled. Checking and creating shortcuts..." -Tag "Get"
        $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $allUsersStartMenu = [Environment]::GetFolderPath('CommonStartMenu')
        Invoke-ShortcutCreation -shortcuts $desktopShortcuts -baseFolder $publicDesktop -locationName "Public Desktop"
        Invoke-ShortcutCreation -shortcuts $startMenuShortcuts -baseFolder $allUsersStartMenu -locationName "Start Menu"
    }

    $exitCode = if ($null -ne $processExitCode) { $processExitCode } else { 0 }
    $exitMeaning = Get-InstallerExitCodeMeaning -exitCode $exitCode
    Write-Log "Installation verified. Exiting with code $exitCode ($exitMeaning) for Intune to process." -Tag "Success"
    Complete-Script -exitCode $exitCode
}
else {
    $exitCode = if ($null -ne $processExitCode) { $processExitCode } else { 1 }
    Write-Log "Registry verification failed. Exiting with installer code $exitCode for Intune to process." -Tag "Error"
    Complete-Script -exitCode $exitCode
}
