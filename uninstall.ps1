# ---------------------------[ Script Start Timestamp ]--------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Configuration ]------------------------------
$applicationName         = "__REGISTRY_DISPLAY_NAME__"
$usePackagedUninstaller  = $false
$installerName           = "setup.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'

# ---------------------------[ UNC Path & Authentication ]---------------------
# Optional: Use when packaged uninstaller is on a network share (Entra-joined devices need creds)
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

# ---------------------------[ File Check Retry Configuration ]------------------
$fileCheckMaxRetries = 5
$fileCheckRetryDelaySeconds = 30

# ---------------------------[ Wildcard Matching Configuration ]-----------------
$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) { $applicationName -replace '[\*\?\[\]]', '' } else {
    $applicationName
}

# ---------------------------[ Logging Configuration ]--------------------------
$scriptName       = $applicationNameClean
$logFileName      = "uninstall.log"
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

# ---------------------------[ Exit Function ]------------------------------
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
        Write-Log 'UNC path not accessible. Set $useUncAuth = $true and provide $uncCredential (PSCredential) for Entra-joined devices.' -Tag "Error"
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

# ---------------------------[ File Path Retry Check Function ]-------------------
function Test-PathWithRetry {
    [CmdletBinding()]
    param(
        [string]$path,
        [int]$maxRetries = 5,
        [int]$retryDelaySeconds = 30
    )

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if (Test-Path -Path $path) {
            if ($attempt -gt 1) {
                Write-Log "Path became available on attempt $attempt of ${maxRetries}: $path" -Tag "Success"
            }
            return $true
        }

        if ($attempt -lt $maxRetries) {
            Write-Log "Path not found (attempt $attempt of $maxRetries): $path. Retrying in $retryDelaySeconds seconds..." -Tag "Info"
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }

    return $false
}

# ---------------------------[ Registry Check Function ]-----------------------
function Test-ApplicationInRegistry {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [switch]$suppressLogging,
        [bool]$useWildcardMatching = $false
    )
    if (-not $suppressLogging) {
        if ($useWildcardMatching) {
            Write-Log "Checking registry for application '$applicationName' (wildcard matching enabled)." -Tag "Get"
        } else {
            Write-Log "Checking registry for application '$applicationName'." -Tag "Get"
        }
    }
    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Registry path '$registryPath' does not exist, skipping." -Tag "Debug"
            continue
        }
        $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subkeys) { continue }
        foreach ($subkey in $subkeys) {
            $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }
            $displayName = $properties.DisplayName
            $isMatch = if ($useWildcardMatching) { $displayName -like $applicationName } else { $displayName -eq $applicationName }
            if ($isMatch) {
                Write-Log "Application '$applicationName' found in registry at: $($subkey.PSPath)" -Tag "Debug"
                return $true
            }
        }
    }
    Write-Log "Application '$applicationName' not found in registry." -Tag "Debug"
    return $false
}

# ---------------------------[ Post-Uninstall Validation Function ]-------------
function Test-PostUninstallValidation {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [int]$maxRetries = 3,
        [int]$retryDelay = 5,
        [bool]$useWildcardMatching = $false
    )
    Write-Log "Performing post-uninstall validation..." -Tag "Info"
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "Validation check $attempt of $maxRetries after $retryDelay seconds..." -Tag "Info"
            Start-Sleep -Seconds $retryDelay
        }
        $applicationRemoved = -not (Test-ApplicationInRegistry -applicationName $applicationName -registryPaths $registryPaths -suppressLogging -useWildcardMatching $useWildcardMatching)
        if ($applicationRemoved) {
            Write-Log "Post-uninstall validation successful: Application removed from registry." -Tag "Success"
            return $true
        }
        Write-Log "Application still present in registry (validation check $attempt of $maxRetries)." -Tag "Info"
    }
    Write-Log "Post-uninstall validation failed: Application still present in registry after $maxRetries validation attempts." -Tag "Error"
    return $false
}

# ---------------------------[ Execute Uninstall Process Function ]-------------
function Invoke-UninstallProcess {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [string]$context = "Uninstall"
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

# ---------------------------[ Convert UninstallString Function ]---------------
function ConvertFrom-UninstallString {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    $UninstallString = $UninstallString.Trim()
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString is empty or whitespace." -Tag "Error"
        return @{
            FilePath  = ""
            Arguments = ""
        }
    }

    if ($UninstallString -match '^"([^"]+)"\s*(.*)$') {
        $filePath = $matches[1]
        $arguments = $matches[2].Trim()
    }
    elseif ($UninstallString -match '^([^\s"]+\.(exe|msi|bat|cmd))(?:\s+(.*))?$') {
        $filePath = $matches[1]
        $arguments = if ($matches[3]) { $matches[3].Trim() } else { "" }
    }
    else {
        $parts = $UninstallString -split '\s+', 2
        $filePath = $parts[0]
        $arguments = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    }

    if ([string]::IsNullOrWhiteSpace($filePath)) {
        Write-Log "Failed to parse executable path from UninstallString: $UninstallString" -Tag "Error"
    }

    return @{
        FilePath  = $filePath
        Arguments = $arguments
    }
}

# ---------------------------[ Detect MSI Function ]----------------------------
function Test-IsMsiInstaller {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [string]$uninstallString
    )

    $stringToCheck = $uninstallString
    if ([string]::IsNullOrWhiteSpace($stringToCheck) -and $argumentList) {
        $stringToCheck = $argumentList
    }
    if ([string]::IsNullOrWhiteSpace($stringToCheck) -and $filePath) {
        $stringToCheck = $filePath
    }

    if ($filePath -and $filePath -match 'msiexec\.exe') { return $true }
    if ($filePath -and $filePath -match '\.msi$') { return $true }
    if ($argumentList -and $argumentList -match '(?:^|\s|/)[xi](?:\s|$|\{)') { return $true }
    if ($uninstallString -and $uninstallString -match '(?:^|"|\\|\s)msiexec\.exe(?:\s|"|/|$)') { return $true }
    if ($uninstallString -and $uninstallString -match '\/[iIlLxX]\s*\{[a-fA-F0-9\-]+\}') { return $true }
    if ($uninstallString -and $uninstallString -match '\.msi(?:\s|"|$)') { return $true }

    return $false
}

# ---------------------------[ Find Application Uninstall/Modify Command ]--------
function Get-ApplicationUninstallString {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [string]$excludeUninstallString = $null,
        [bool]$useWildcardMatching = $false
    )

    if ($useWildcardMatching) {
        Write-Log "Searching registry for application '$applicationName' (wildcard matching enabled)..." -Tag "Get"
    } else {
        Write-Log "Searching registry for application '$applicationName'..." -Tag "Get"
    }

    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Registry path '$registryPath' does not exist, skipping." -Tag "Debug"
            continue
        }

        Write-Log "Searching in registry path: $registryPath" -Tag "Get"

        $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subkeys) {
            Write-Log "No subkeys found in $registryPath" -Tag "Debug"
            continue
        }

        foreach ($subkey in $subkeys) {
            $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }

            $displayName = $properties.DisplayName
            $uninstallString = $properties.UninstallString
            $modifyPath = $properties.ModifyPath

            if ($displayName) {
                Write-Log "Found installed product: '$displayName'" -Tag "Debug"
            }

            $isMatch = if ($useWildcardMatching) {
                $displayName -like $applicationName
            } else {
                $displayName -eq $applicationName
            }

            if (-not $isMatch) { continue }

            Write-Log "Found application '$displayName'" -Tag "Success"

            if (-not [string]::IsNullOrWhiteSpace($excludeUninstallString)) {
                $currentNormalized = $uninstallString.Trim().ToLowerInvariant()
                $excludeNormalized = $excludeUninstallString.Trim().ToLowerInvariant()
                if ($currentNormalized -eq $excludeNormalized) {
                    Write-Log "Skipping UninstallString (exact match with excluded value)." -Tag "Debug"
                    continue
                }
                if ($currentNormalized -match '/[xi]\{([a-f0-9\-]+)\}') {
                    $currentGuid = $matches[1]
                    if ($excludeNormalized -match '/[xi]\{([a-f0-9\-]+)\}') {
                        $excludeGuid = $matches[1]
                        if ($currentGuid -eq $excludeGuid) {
                            Write-Log "Skipping UninstallString (MSI product code matches excluded value)." -Tag "Debug"
                            continue
                        }
                    }
                }
            }

            $chosenString = Get-BestUninstallCommand -uninstallString $uninstallString -modifyPath $modifyPath
            if (-not [string]::IsNullOrWhiteSpace($chosenString)) {
                return $chosenString
            }

            Write-Log "No valid UninstallString or ModifyPath for '$applicationName'." -Tag "Debug"
        }
    }

    return $null
}

# ---------------------------[ Select Best Uninstall Command ]--------------------
function Get-BestUninstallCommand {
    [CmdletBinding()]
    param(
        [string]$uninstallString,
        [string]$modifyPath
    )

    $uninstallTrimmed = if ($uninstallString) { $uninstallString.Trim() } else { "" }
    $modifyTrimmed = if ($modifyPath) { $modifyPath.Trim() } else { "" }

    $uninstallIsMsi = Test-IsMsiInstaller -uninstallString $uninstallTrimmed
    $modifyIsMsi = Test-IsMsiInstaller -uninstallString $modifyTrimmed

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and $uninstallIsMsi) {
        Write-Log "Using UninstallString (MSI detected)." -Tag "Info"
        return $uninstallTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and [string]::IsNullOrWhiteSpace($modifyTrimmed)) {
        Write-Log "Using UninstallString (ModifyPath not available)." -Tag "Info"
        return $uninstallTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not $uninstallIsMsi -and -not [string]::IsNullOrWhiteSpace($modifyTrimmed) -and $modifyIsMsi) {
        Write-Log "UninstallString is non-MSI. Trying ModifyPath (MSI detected) for uninstall." -Tag "Info"
        return $modifyTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not $uninstallIsMsi -and (-not [string]::IsNullOrWhiteSpace($modifyTrimmed) -and -not $modifyIsMsi)) {
        Write-Log "ModifyPath is also non-MSI. Falling back to UninstallString." -Tag "Info"
        return $uninstallTrimmed
    }

    if ([string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not [string]::IsNullOrWhiteSpace($modifyTrimmed)) {
        if ($modifyIsMsi) {
            Write-Log "UninstallString empty. Using ModifyPath (MSI detected) for uninstall." -Tag "Info"
        } else {
            Write-Log "UninstallString empty. Using ModifyPath as last resort." -Tag "Info"
        }
        return $modifyTrimmed
    }

    return $null
}

# ---------------------------[ Resolve System Executable Function ]-------------
function Resolve-SystemExecutable {
    [CmdletBinding()]
    param(
        [string]$ExecutableName
    )

    if ([System.IO.Path]::IsPathRooted($ExecutableName) -and (Test-Path -Path $ExecutableName)) {
        return $ExecutableName
    }

    $fileName = [System.IO.Path]::GetFileName($ExecutableName)
    $fileNameLower = $fileName.ToLowerInvariant()

    if ($fileNameLower -eq "msiexec.exe") {
        $system32Path = Join-Path -Path $env:SystemRoot -ChildPath "System32\msiexec.exe"
        if (Test-Path -Path $system32Path) {
            Write-Log "Resolved '$ExecutableName' to system path: $system32Path" -Tag "Debug"
            return $system32Path
        }
        $syswow64Path = Join-Path -Path $env:SystemRoot -ChildPath "SysWOW64\msiexec.exe"
        if (Test-Path -Path $syswow64Path) {
            Write-Log "Resolved '$ExecutableName' to system path: $syswow64Path" -Tag "Debug"
            return $syswow64Path
        }
    }

    try {
        $command = Get-Command -Name $fileName -ErrorAction Stop
        if ($command -and $command.Source) {
            Write-Log "Resolved '$ExecutableName' via PATH to: $($command.Source)" -Tag "Debug"
            return $command.Source
        }
    }
    catch {
        Write-Log "Get-Command could not resolve '$fileName'; using original path." -Tag "Debug"
    }
    return $ExecutableName
}

# ---------------------------[ Process UninstallString Function ]---------------
function Get-ProcessedUninstallerCommand {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString is empty or whitespace." -Tag "Error"
        return $null
    }

    Write-Log "Original uninstall string: $UninstallString" -Tag "Debug"
    $uninstallString = $uninstallString.Trim()
    $isMsi = Test-IsMsiInstaller -UninstallString $uninstallString

    if ($isMsi) {
        Write-Log "MSI-based uninstaller detected. Ensuring MSI uninstall arguments are present." -Tag "Info"

        # ModifyPath often has /i or /I (install); we need /X (uninstall). Also handle /l (font/typo for I).
        if ($uninstallString -match '/[iIlL]\s*\{([a-fA-F0-9\-]+)\}') {
            $productCode = $matches[1]
            $uninstallString = $uninstallString -replace '/[iIlL]\s*\{', '/X{'
            Write-Log "Corrected MSI switch from /I (install) to /X (uninstall) for product code: $productCode" -Tag "Info"
        }
        # MSI path format: /i "path\to\file.msi" -> /x for uninstall
        elseif ($uninstallString -match '/[iIlL]\s+"') {
            $uninstallString = $uninstallString -replace '/([iIlL])\s+', '/x '
            Write-Log "Corrected MSI switch from /I (install) to /X (uninstall) for MSI path." -Tag "Info"
        }

        if ($uninstallString -notmatch '/(?:qn|quiet|q|norestart)(?:\s|$|/)') {
            $uninstallString += " $uninstallerArgumentsMsi"
            Write-Log "Appended MSI uninstall arguments: $uninstallerArgumentsMsi" -Tag "Debug"
        }
        else {
            Write-Log "MSI uninstall string already contains quiet flag." -Tag "Debug"
        }
    }
    else {
        Write-Log "Non-MSI uninstaller detected. Checking if EXE uninstall arguments are needed." -Tag "Info"
        $existingArgs = $uninstallString -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        $providedArgs = $uninstallerArgumentsExe -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        $argsToAppend = @()
        foreach ($arg in $providedArgs) {
            if ($existingArgs -contains $arg) {
                Write-Log "Argument '$arg' already exists in UninstallString. Skipping to avoid duplication." -Tag "Debug"
            }
            else {
                $argsToAppend += $arg
            }
        }
        
        if ($argsToAppend.Count -gt 0) {
            $argsToAppendString = $argsToAppend -join ' '
            $uninstallString += " $argsToAppendString"
            Write-Log "Appended EXE uninstall arguments: $argsToAppendString" -Tag "Debug"
        }
        else {
            Write-Log "All EXE uninstall arguments already exist in UninstallString. Skipping append to avoid duplication." -Tag "Debug"
        }
    }

    Write-Log "Final uninstall string: $uninstallString" -Tag "Debug"
    $parsedUninstall = ConvertFrom-UninstallString -UninstallString $uninstallString
    $uninstallerPath = $parsedUninstall.FilePath
    $uninstallerArgs = $parsedUninstall.Arguments

    if ([string]::IsNullOrWhiteSpace($uninstallerPath)) {
        Write-Log "Failed to parse executable path from UninstallString." -Tag "Error"
        return $null
    }

    if ($uninstallerPath -match '\.msi$') {
        $uninstallerPath = [System.Environment]::ExpandEnvironmentVariables($uninstallerPath)
        if (-not (Test-PathWithRetry -path $uninstallerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
            Write-Log "MSI file not found at path: $uninstallerPath" -Tag "Error"
            return $null
        }
        $escapedPath = $uninstallerPath -replace '"', '""'
        $uninstallerPath = Resolve-SystemExecutable -ExecutableName "msiexec.exe"
        $uninstallerArgs = "/x `"$escapedPath`" $uninstallerArgumentsMsi"
        Write-Log "MSI path detected. Using msiexec /x for uninstall." -Tag "Info"
    }
    else {
        $uninstallerPath = [System.Environment]::ExpandEnvironmentVariables($uninstallerPath)
        $uninstallerPath = Resolve-SystemExecutable -ExecutableName $uninstallerPath

        if (-not (Test-PathWithRetry -path $uninstallerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
            Write-Log "Uninstaller executable not found at path: $uninstallerPath" -Tag "Error"
            return $null
        }
    }

    Write-Log "Parsed uninstaller path: $uninstallerPath" -Tag "Debug"
    Write-Log "Parsed uninstaller arguments: $uninstallerArgs" -Tag "Debug"

    $isMsiFinal = Test-IsMsiInstaller -FilePath $uninstallerPath -ArgumentList $uninstallerArgs

    return @{
        FilePath  = $uninstallerPath
        Arguments = $uninstallerArgs
        IsMsi     = $isMsiFinal
    }
}

# ---------------------------[ Execute Uninstall with Validation Function ]-----
function Invoke-UninstallWithValidation {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [bool]$isMsi,
        [string]$applicationName,
        [string[]]$registryPaths,
        [string]$context = "Uninstall",
        [string]$originalUninstallString = $null,
        [bool]$useWildcardMatching = $false
    )

    try {
        $process = Invoke-UninstallProcess -filePath $filePath -argumentList $argumentList -context $context

        if ($null -eq $process) {
            return @{ Success = $false; ExitCode = 1 }
        }

        $isSuccessCode = $process.ExitCode -eq 0 -or ($isMsi -and $process.ExitCode -eq 3010)

        if ($isSuccessCode) {
            if ($process.ExitCode -eq 3010) {
                Write-Log "Uninstall completed but reboot is required (exit code 3010)." -Tag "Info"
            }
            else {
                Write-Log "$applicationName uninstall process completed with exit code: $($process.ExitCode)" -Tag "Success"
            }

            $validationParams = @{
                applicationName       = $applicationName
                registryPaths         = $registryPaths
                useWildcardMatching   = $useWildcardMatching
            }
            $validationSuccess = Test-PostUninstallValidation @validationParams

            if ($validationSuccess) {
                return @{ Success = $true; ExitCode = $process.ExitCode }
            }
            else {
                Write-Log "Uninstall process completed but validation failed." -Tag "Error"
                
                Write-Log "Attempting fallback: Searching for alternative UninstallString..." -Tag "Info"
                
                if ([string]::IsNullOrWhiteSpace($originalUninstallString)) {
                    Write-Log "Original UninstallString not provided. Cannot search for alternative." -Tag "Error"
                    return @{ Success = $false; ExitCode = 1 }
                }

                $alternativeParams = @{
                    applicationName         = $applicationName
                    registryPaths           = $registryPaths
                    excludeUninstallString  = $originalUninstallString
                    useWildcardMatching     = $useWildcardMatching
                }
                $alternativeUninstallString = Get-ApplicationUninstallString @alternativeParams
                
                if (-not [string]::IsNullOrWhiteSpace($alternativeUninstallString)) {
                    Write-Log "Found alternative UninstallString. Executing fallback uninstall..." -Tag "Info"
                    Write-Log "Alternative UninstallString: $alternativeUninstallString" -Tag "Debug"
                    
                    $fallbackCommand = Get-ProcessedUninstallerCommand -UninstallString $alternativeUninstallString
                    
                    if ($null -ne $fallbackCommand) {
                        Write-Log "Executing fallback uninstaller..." -Tag "Run"
                        $fallbackProcessParams = @{
                            filePath      = $fallbackCommand.FilePath
                            argumentList  = $fallbackCommand.Arguments
                            context       = "Fallback uninstall"
                        }
                        $fallbackProcess = Invoke-UninstallProcess @fallbackProcessParams
                        
                        if ($null -ne $fallbackProcess) {
                            $fallbackSuccessCode = $fallbackProcess.ExitCode -eq 0 -or ($fallbackCommand.IsMsi -and $fallbackProcess.ExitCode -eq 3010)
                            
                            if ($fallbackSuccessCode) {
                                Write-Log "Fallback uninstall completed with exit code: $($fallbackProcess.ExitCode)" -Tag "Success"
                                
                                Write-Log "Re-validating after fallback uninstall..." -Tag "Info"
                                $fallbackValidationParams = @{
                                    applicationName       = $applicationName
                                    registryPaths         = $registryPaths
                                    useWildcardMatching   = $useWildcardMatching
                                }
                                $fallbackValidationSuccess = Test-PostUninstallValidation @fallbackValidationParams
                                
                                if ($fallbackValidationSuccess) {
                                    Write-Log "Fallback uninstall and validation successful." -Tag "Success"
                                    return @{ Success = $true; ExitCode = $fallbackProcess.ExitCode }
                                }
                                else {
                                    Write-Log "Fallback uninstall completed but validation still failed." -Tag "Error"
                                    return @{ Success = $false; ExitCode = 1 }
                                }
                            }
                            else {
                                Write-Log "Fallback uninstall returned exit code: $($fallbackProcess.ExitCode)" -Tag "Error"
                                return @{ Success = $false; ExitCode = 1 }
                            }
                        }
                        else {
                            Write-Log "Fallback uninstall process failed to start." -Tag "Error"
                            return @{ Success = $false; ExitCode = 1 }
                        }
                    }
                    else {
                        Write-Log "Failed to process alternative UninstallString." -Tag "Error"
                        return @{ Success = $false; ExitCode = 1 }
                    }
                }
                else {
                    Write-Log "No alternative UninstallString found. Validation failed." -Tag "Error"
                    return @{ Success = $false; ExitCode = 1 }
                }
            }
        }
        else {
            Write-Log "$context returned exit code: $($process.ExitCode)" -Tag "Error"
            return @{ Success = $false; ExitCode = $process.ExitCode }
        }
    }
    catch {
        Write-Log "$context failed with exception: $($_.Exception.Message)" -Tag "Error"
        Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        return @{ Success = $false; ExitCode = 1 }
    }
}

# ---------------------------[ Prepare Packaged Uninstaller Function ]----------
function Get-PackagedUninstallerCommand {
    [CmdletBinding()]
    param(
        [string]$InstallerPath
    )

    $installerExtension = [System.IO.Path]::GetExtension($InstallerPath)
    Write-Log "Detected packaged installer extension: '$installerExtension'" -Tag "Debug"

    switch ($installerExtension.ToLowerInvariant()) {
        ".msi" {
            Write-Log "Packaged installer identified as MSI. Preparing msiexec uninstall command line." -Tag "Info"
            $filePath = "msiexec.exe"
            # Escape quotes in path if present, then quote the entire path
            $escapedPath = $InstallerPath -replace '"', '""'
            $argumentList = "/x `"$escapedPath`" $uninstallerArgumentsMsi"
            $isMsi = $true
        }
        ".exe" {
            Write-Log "Packaged installer identified as EXE. Using EXE uninstall arguments." -Tag "Info"
            $filePath = $InstallerPath
            $argumentList = $uninstallerArgumentsExe
            $isMsi = $false
        }
        default {
            Write-Log "Unsupported packaged installer extension '$installerExtension'. Only .exe and .msi are supported." -Tag "Error"
            return $null
        }
    }

    Write-Log "Uninstall file: $filePath" -Tag "Debug"
    Write-Log "Uninstall arguments: $argumentList" -Tag "Debug"

    return @{
        FilePath  = $filePath
        Arguments = $argumentList
        IsMsi     = $isMsi
    }
}

# ---------------------------[ Script Start ]-----------------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

if ([string]::IsNullOrWhiteSpace($applicationName)) {
    Write-Log 'Application name is not configured. Please set $applicationName.' -Tag "Error"
    Complete-Script -exitCode 1
}

if ($usePackagedUninstaller) {

    if (-not (Test-UncPathAccess -path $installerPath -useUncAuth $useUncAuth -uncCredential $uncCredential)) {
        Complete-Script -exitCode 1
    }

    if (-not (Test-PathWithRetry -path $installerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
        Write-Log "Packaged installer not found at path: $installerPath" -Tag "Error"
        Complete-Script -exitCode 1
    }

    Write-Log "Packaged installer found at path: $installerPath" -Tag "Success"

    $uninstallerCommand = Get-PackagedUninstallerCommand -InstallerPath $installerPath
    if ($null -eq $uninstallerCommand) {
        Complete-Script -exitCode 1
    }

    $uninstallParams = @{
        filePath              = $uninstallerCommand.FilePath
        argumentList          = $uninstallerCommand.Arguments
        isMsi                 = $uninstallerCommand.IsMsi
        applicationName       = $applicationName
        registryPaths         = $registrySearchPaths
        context               = "Packaged uninstall"
        useWildcardMatching   = $useWildcardMatching
    }
    $result = Invoke-UninstallWithValidation @uninstallParams

    Complete-Script -exitCode $result.ExitCode
}
else {

    $uninstallString = Get-ApplicationUninstallString -ApplicationName $applicationName -registryPaths $registrySearchPaths -useWildcardMatching $useWildcardMatching

    if ($null -eq $uninstallString) {
        Write-Log "Application '$applicationName' not found in registry or UninstallString is missing." -Tag "Error"
        Complete-Script -exitCode 1
    }

    $uninstallerCommand = Get-ProcessedUninstallerCommand -UninstallString $uninstallString
    if ($null -eq $uninstallerCommand) {
        Complete-Script -exitCode 1
    }

    $uninstallParams = @{
        filePath                  = $uninstallerCommand.FilePath
        argumentList              = $uninstallerCommand.Arguments
        isMsi                     = $uninstallerCommand.IsMsi
        applicationName           = $applicationName
        registryPaths             = $registrySearchPaths
        context                   = "Registry-based uninstall"
        originalUninstallString   = $uninstallString
        useWildcardMatching       = $useWildcardMatching
    }
    $result = Invoke-UninstallWithValidation @uninstallParams

    Complete-Script -exitCode $result.ExitCode
}
