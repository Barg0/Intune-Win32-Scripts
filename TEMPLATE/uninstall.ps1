# ===========================[ Script Start Timestamp ]===========================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]===========================

# Name of application (used for logging, registry lookup, and post-uninstall validation)
$applicationName              = "__REGISTRY_DISPLAY_NAME__"

# Use the EXE/MSI bundled inside the IntuneWin package for uninstall?
# $true  = use packaged installer for uninstall (registry still used for validation)
# $false = use registry UninstallString detection to find and execute uninstaller
$usePackagedUninstaller       = $false

# Packaged uninstaller configuration (used only when $usePackagedUninstaller = $true)
# This file must be included next to the script in the IntuneWin package
$installerName                = "setup.exe"
$installerPath                = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# Uninstaller arguments
$uninstallerArgumentsExe      = "/uninstall /silent"               # For non-MSI uninstallers (packaged or registry-based)
$uninstallerArgumentsMsi      = "/qn"                              # For MSI uninstall (msiexec /x ...)

# Registry locations to search for uninstall entries
# Used for: registry-based uninstall mode AND post-uninstall validation in both modes
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Wildcard support: If $applicationName contains *, use wildcard matching in registry searches
# The clean name (without *) is used for log paths and folder names
$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) {
    # Remove wildcard characters for use in file paths
    $applicationName -replace '[\*\?\[\]]', ''
} else {
    $applicationName
}

# ===========================[ Logging Configuration ]===========================
$scriptName       = $applicationNameClean
$logFileName      = "uninstall.log"

# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $false to hide DEBUG logs
$logGet        = $true    # Enable/disable all [Get] logs
$logRun        = $true    # Enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

# Ensure log directory exists
if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    try {
        $null = New-Item -ItemType Directory -Path $logFileDirectory -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to create log directory '$logFileDirectory': $($_.Exception.Message)"
        # Continue execution - logging will fail but script should continue
    }
}

# ===========================[ Logging Function ]===========================
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

    $logMessage = "$timestamp [  $rawTag ] $message"

    if ($enableLogFile) {
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            # Logging must never block script execution - silently fail if log file is locked
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ===========================[ Exit Function ]===============================
function Stop-Script {
    [CmdletBinding()]
    param(
        [int]$exitCode
    )

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}

# ===========================[ Registry Check Function ]===============================
function Test-ApplicationInRegistry {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths,
        [switch]$SuppressLogging,
        [bool]$UseWildcardMatching = $false
    )

    if (-not $SuppressLogging) {
        if ($UseWildcardMatching) {
            Write-Log "Checking registry for application '$ApplicationName' (wildcard matching enabled)." -Tag "Get"
        } else {
            Write-Log "Checking registry for application '$ApplicationName'." -Tag "Get"
        }
    }

    foreach ($registryPath in $RegistryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Registry path '$registryPath' does not exist, skipping." -Tag "Debug"
            continue
        }

        $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subkeys) {
            continue
        }

        foreach ($subkey in $subkeys) {
            $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }

            $displayName = $properties.DisplayName

            # Use wildcard matching if enabled, otherwise exact match
            $isMatch = if ($UseWildcardMatching) {
                $displayName -like $ApplicationName
            } else {
                $displayName -eq $ApplicationName
            }

            if ($isMatch) {
                Write-Log "Application '$ApplicationName' found in registry at: $($subkey.PSPath)" -Tag "Debug"
                return $true
            }
        }
    }

    Write-Log "Application '$ApplicationName' not found in registry." -Tag "Debug"
    return $false
}

# ===========================[ Parse UninstallString Function ]===============================
function Parse-UninstallString {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    # Remove leading/trailing whitespace
    $UninstallString = $UninstallString.Trim()

    # Validate input
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString is empty or whitespace." -Tag "Error"
        return @{
            FilePath  = ""
            Arguments = ""
        }
    }

    # Handle quoted executable paths (e.g., "C:\Program Files\App\uninstall.exe" /silent)
    if ($UninstallString -match '^"([^"]+)"\s*(.*)$') {
        $filePath = $matches[1]
        $arguments = $matches[2].Trim()
    }
    # Handle unquoted executable paths (e.g., C:\App\uninstall.exe /silent)
    # Note: This regex won't handle paths with spaces that aren't quoted - fallback will handle those
    elseif ($UninstallString -match '^([^\s"]+\.(exe|msi|bat|cmd))(?:\s+(.*))?$') {
        $filePath = $matches[1]
        $arguments = if ($matches[3]) { $matches[3].Trim() } else { "" }
    }
    else {
        # Fallback: split on first space (may not handle paths with spaces correctly)
        $parts = $UninstallString -split '\s+', 2
        $filePath = $parts[0]
        $arguments = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    }

    # Validate parsed filePath
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        Write-Log "Failed to parse executable path from UninstallString: $UninstallString" -Tag "Error"
    }

    return @{
        FilePath  = $filePath
        Arguments = $arguments
    }
}

# ===========================[ Execute Uninstall Process Function ]===============================
function Invoke-UninstallProcess {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$Context = "Uninstall"
    )

    # Validate FilePath
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        Write-Log "FilePath is empty or null. Cannot start $Context process." -Tag "Error"
        return $null
    }

    Write-Log "Starting $Context process: '$FilePath' $ArgumentList" -Tag "Run"

    # Use -PassThru to capture process object and exit code
    # This is CRITICAL in SYSTEM context where we can't see the process interactively
    # If ArgumentList is empty, pass $null instead of empty string
    $processParams = @{
        FilePath     = $FilePath
        Wait         = $true
        PassThru     = $true
        NoNewWindow  = $true
    }
    
    if (-not [string]::IsNullOrWhiteSpace($ArgumentList)) {
        $processParams['ArgumentList'] = $ArgumentList
    }
    
    $process = Start-Process @processParams

    if ($null -eq $process) {
        Write-Log "Start-Process did not return a process object. $Context result unknown." -Tag "Error"
        return $null
    }

    Write-Log "$Context process ID: $($process.Id)" -Tag "Debug"
    Write-Log "$Context exit code: $($process.ExitCode)" -Tag "Info"

    return $process
}

# ===========================[ Post-Uninstall Validation Function ]===============================
function Test-PostUninstallValidation {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5,
        [bool]$UseWildcardMatching = $false
    )

    Write-Log "Performing post-uninstall validation..." -Tag "Info"

    # Check registry with retries (some uninstallers take time to remove registry keys after process exit)
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "Validation check $attempt of $MaxRetries after $RetryDelay seconds..." -Tag "Info"
            Start-Sleep -Seconds $RetryDelay
        }

        $applicationRemoved = -not (Test-ApplicationInRegistry -ApplicationName $ApplicationName -RegistryPaths $RegistryPaths -SuppressLogging -UseWildcardMatching $UseWildcardMatching)

        if ($applicationRemoved) {
            Write-Log "Post-uninstall validation successful: Application removed from registry." -Tag "Success"
            return $true
        }
        else {
            Write-Log "Application still present in registry (validation check $attempt of $MaxRetries)." -Tag "Info"
        }
    }

    Write-Log "Post-uninstall validation failed: Application still present in registry after $MaxRetries validation attempts." -Tag "Error"
    return $false
}

# ===========================[ Detect MSI Function ]===============================
function Test-IsMsiInstaller {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$UninstallString
    )

    # Check if msiexec.exe is in the path or arguments
    # Use word boundaries or specific patterns to avoid false positives
    
    # Check FilePath for msiexec.exe
    if ($FilePath -and $FilePath -match "msiexec\.exe") {
        return $true
    }
    
    # Check ArgumentList for MSI uninstall argument (/x) - must be at start or after space/slash
    if ($ArgumentList -and $ArgumentList -match '(?:^|\s|/)x(?:\s|$|/)') {
        return $true
    }
    
    # Check UninstallString for msiexec.exe pattern
    if ($UninstallString -and $UninstallString -match '(?:^|"|\\|\s)msiexec\.exe(?:\s|"|/|$)') {
        return $true
    }
    
    return $false
}

# ===========================[ Find Application in Registry Function ]===============================
function Get-ApplicationUninstallString {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths,
        [string]$ExcludeUninstallString = $null,
        [bool]$UseWildcardMatching = $false
    )

    if ($UseWildcardMatching) {
        Write-Log "Searching registry for application '$ApplicationName' (wildcard matching enabled)..." -Tag "Get"
    } else {
        Write-Log "Searching registry for application '$ApplicationName'..." -Tag "Get"
    }

    foreach ($registryPath in $RegistryPaths) {
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

            if ($displayName) {
                Write-Log "Found installed product: '$displayName'" -Tag "Debug"
            }

            # Use wildcard matching if enabled, otherwise exact match
            $isMatch = if ($UseWildcardMatching) {
                $displayName -like $ApplicationName
            } else {
                $displayName -eq $ApplicationName
            }

            if ($isMatch) {
                Write-Log "Found application '$displayName'" -Tag "Success"
                
                if ([string]::IsNullOrWhiteSpace($uninstallString)) {
                    Write-Log "UninstallString missing or empty for '$ApplicationName'." -Tag "Debug"
                    continue
                }

                # If ExcludeUninstallString is provided, skip if this matches it
                # Compare both exact match and normalized versions (handle case differences and path variations)
                if (-not [string]::IsNullOrWhiteSpace($ExcludeUninstallString)) {
                    $currentNormalized = $uninstallString.Trim().ToLowerInvariant()
                    $excludeNormalized = $ExcludeUninstallString.Trim().ToLowerInvariant()
                    
                    # Exact match
                    if ($currentNormalized -eq $excludeNormalized) {
                        Write-Log "Skipping UninstallString (exact match with excluded value)." -Tag "Debug"
                        continue
                    }
                    
                    # For MSI, also check if the GUID/product code matches (extract from /X{...} or /I{...})
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

                return $uninstallString
            }
        }
    }

    return $null
}

# ===========================[ Resolve System Executable Function ]===============================
function Resolve-SystemExecutable {
    [CmdletBinding()]
    param(
        [string]$ExecutableName
    )

    # Normalize executable name to lowercase for comparison
    $executableNameLower = $ExecutableName.ToLowerInvariant()

    # If path is already absolute and exists, return as-is
    if ([System.IO.Path]::IsPathRooted($ExecutableName) -and (Test-Path -Path $ExecutableName)) {
        return $ExecutableName
    }

    # Extract just the filename if a path was provided
    $fileName = [System.IO.Path]::GetFileName($ExecutableName)
    $fileNameLower = $fileName.ToLowerInvariant()

    # Common system executables that may be referenced without full path
    # For MSI, always resolve to system32/syswow64 paths
    if ($fileNameLower -eq "msiexec.exe") {
        # Try System32 first (64-bit on 64-bit systems, or 32-bit on 32-bit systems)
        $system32Path = Join-Path -Path $env:SystemRoot -ChildPath "System32\msiexec.exe"
        if (Test-Path -Path $system32Path) {
            Write-Log "Resolved '$ExecutableName' to system path: $system32Path" -Tag "Debug"
            return $system32Path
        }

        # Try SysWOW64 (32-bit on 64-bit systems)
        $syswow64Path = Join-Path -Path $env:SystemRoot -ChildPath "SysWOW64\msiexec.exe"
        if (Test-Path -Path $syswow64Path) {
            Write-Log "Resolved '$ExecutableName' to system path: $syswow64Path" -Tag "Debug"
            return $syswow64Path
        }
    }

    # Try Get-Command to find executable in PATH
    try {
        $command = Get-Command -Name $fileName -ErrorAction Stop
        if ($command -and $command.Source) {
            Write-Log "Resolved '$ExecutableName' via PATH to: $($command.Source)" -Tag "Debug"
            return $command.Source
        }
    }
    catch {
        # Get-Command failed, continue to return original
    }

    # Return original if we couldn't resolve it
    return $ExecutableName
}

# ===========================[ Process UninstallString Function ]===============================
function Get-ProcessedUninstallerCommand {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    # Validate input
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString is empty or whitespace." -Tag "Error"
        return $null
    }

    Write-Log "Original uninstall string: $UninstallString" -Tag "Debug"

    $uninstallString = $uninstallString.Trim()

    # Detect MSI and append appropriate arguments
    $isMsi = Test-IsMsiInstaller -UninstallString $uninstallString

    if ($isMsi) {
        Write-Log "MSI-based uninstaller detected. Ensuring MSI uninstall arguments are present." -Tag "Info"

        # Fix incorrect MSI switch: Replace /I (install) with /X (uninstall) if present
        # Some registry entries incorrectly use /I instead of /X for uninstallation
        # Match case-insensitively: /I, /i, /I{, /i{
        if ($uninstallString -match '/[iI]\{([a-fA-F0-9\-]+)\}') {
            $productCode = $matches[1]
            # Replace /I or /i with /X (simple replacement - case-insensitive)
            $uninstallString = $uninstallString -replace '/[iI]\{', '/X{'
            Write-Log "Corrected MSI switch from /I (install) to /X (uninstall) for product code: $productCode" -Tag "Info"
        }

        # Check for any quiet flag: /qn, /quiet, /q, /norestart
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
        
        # Check for duplicate arguments before appending
        # Split both strings into tokens for comparison (case-insensitive)
        $existingArgs = $uninstallString -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        $providedArgs = $uninstallerArgumentsExe -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        
        # Check if any of the provided arguments already exist in the uninstall string
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

    # Parse the UninstallString to extract executable and arguments
    $parsedUninstall = Parse-UninstallString -UninstallString $uninstallString
    $uninstallerPath = $parsedUninstall.FilePath
    $uninstallerArgs = $parsedUninstall.Arguments

    # Validate parsed FilePath
    if ([string]::IsNullOrWhiteSpace($uninstallerPath)) {
        Write-Log "Failed to parse executable path from UninstallString." -Tag "Error"
        return $null
    }

    Write-Log "Parsed uninstaller path: $uninstallerPath" -Tag "Debug"
    Write-Log "Parsed uninstaller arguments: $uninstallerArgs" -Tag "Debug"

    # Expand environment variables in path (e.g., %ProgramFiles% -> C:\Program Files)
    $uninstallerPath = [System.Environment]::ExpandEnvironmentVariables($uninstallerPath)

    # Resolve system executables (e.g., msiexec.exe -> C:\Windows\System32\msiexec.exe)
    $uninstallerPath = Resolve-SystemExecutable -ExecutableName $uninstallerPath

    # Validate the uninstaller executable exists
    if (-not (Test-Path -Path $uninstallerPath)) {
        Write-Log "Uninstaller executable not found at path: $uninstallerPath" -Tag "Error"
        return $null
    }

    # Determine if this is an MSI uninstaller (for exit code handling)
    $isMsiFinal = Test-IsMsiInstaller -FilePath $uninstallerPath -ArgumentList $uninstallerArgs

    return @{
        FilePath  = $uninstallerPath
        Arguments = $uninstallerArgs
        IsMsi     = $isMsiFinal
    }
}

# ===========================[ Execute Uninstall with Validation Function ]===============================
function Invoke-UninstallWithValidation {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [bool]$IsMsi,
        [string]$ApplicationName,
        [string[]]$RegistryPaths,
        [string]$Context = "Uninstall",
        [string]$OriginalUninstallString = $null,
        [bool]$UseWildcardMatching = $false
    )

    try {
        $process = Invoke-UninstallProcess -FilePath $FilePath `
                                           -ArgumentList $ArgumentList `
                                           -Context $Context

        if ($null -eq $process) {
            return @{ Success = $false; ExitCode = 1 }
        }

        # Check if exit code indicates we should proceed with validation
        # Exit codes are passed through to Stop-Script for Intune to interpret
        $isSuccessCode = $process.ExitCode -eq 0 -or ($IsMsi -and $process.ExitCode -eq 3010)

        if ($isSuccessCode) {
            if ($process.ExitCode -eq 3010) {
                Write-Log "Uninstall completed but reboot is required (exit code 3010)." -Tag "Info"
            }
            else {
                Write-Log "$ApplicationName uninstall process completed with exit code: $($process.ExitCode)" -Tag "Success"
            }

            $validationSuccess = Test-PostUninstallValidation -ApplicationName $ApplicationName `
                                                               -RegistryPaths $RegistryPaths `
                                                               -UseWildcardMatching $UseWildcardMatching

            if ($validationSuccess) {
                # Pass the original exit code to Stop-Script (Intune will interpret it)
                return @{ Success = $true; ExitCode = $process.ExitCode }
            }
            else {
                Write-Log "Uninstall process completed but validation failed." -Tag "Error"
                
                # Safety net: Check for alternative UninstallString and try it
                Write-Log "Attempting fallback: Searching for alternative UninstallString..." -Tag "Info"
                
                # Use the exact OriginalUninstallString from registry (no approximation)
                if ([string]::IsNullOrWhiteSpace($OriginalUninstallString)) {
                    Write-Log "Original UninstallString not provided. Cannot search for alternative." -Tag "Error"
                    return @{ Success = $false; ExitCode = 1 }
                }
                
                $alternativeUninstallString = Get-ApplicationUninstallString -ApplicationName $ApplicationName `
                                                                           -RegistryPaths $RegistryPaths `
                                                                           -ExcludeUninstallString $OriginalUninstallString `
                                                                           -UseWildcardMatching $UseWildcardMatching
                
                if (-not [string]::IsNullOrWhiteSpace($alternativeUninstallString)) {
                    Write-Log "Found alternative UninstallString. Executing fallback uninstall..." -Tag "Info"
                    Write-Log "Alternative UninstallString: $alternativeUninstallString" -Tag "Debug"
                    
                    $fallbackCommand = Get-ProcessedUninstallerCommand -UninstallString $alternativeUninstallString
                    
                    if ($null -ne $fallbackCommand) {
                        Write-Log "Executing fallback uninstaller..." -Tag "Run"
                        $fallbackProcess = Invoke-UninstallProcess -FilePath $fallbackCommand.FilePath `
                                                                   -ArgumentList $fallbackCommand.Arguments `
                                                                   -Context "Fallback uninstall"
                        
                        if ($null -ne $fallbackProcess) {
                            $fallbackSuccessCode = $fallbackProcess.ExitCode -eq 0 -or ($fallbackCommand.IsMsi -and $fallbackProcess.ExitCode -eq 3010)
                            
                            if ($fallbackSuccessCode) {
                                Write-Log "Fallback uninstall completed with exit code: $($fallbackProcess.ExitCode)" -Tag "Success"
                                
                                # Re-validate after fallback uninstall
                                Write-Log "Re-validating after fallback uninstall..." -Tag "Info"
                                $fallbackValidationSuccess = Test-PostUninstallValidation -ApplicationName $ApplicationName `
                                                                                        -RegistryPaths $RegistryPaths `
                                                                                        -UseWildcardMatching $UseWildcardMatching
                                
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
            Write-Log "$Context returned exit code: $($process.ExitCode)" -Tag "Error"
            # Pass the actual exit code to Stop-Script (Intune will interpret it)
            return @{ Success = $false; ExitCode = $process.ExitCode }
        }
    }
    catch {
        Write-Log "$Context failed with exception: $($_.Exception.Message)" -Tag "Error"
        Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        return @{ Success = $false; ExitCode = 1 }
    }
}

# ===========================[ Prepare Packaged Uninstaller Function ]===============================
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

# ===========================[ Script Start ]===============================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

Write-Log "Log file: '$logFile'" -Tag "Debug"

# Validate required configuration
if ([string]::IsNullOrWhiteSpace($applicationName)) {
    Write-Log "Application name is not configured. Please set `$applicationName." -Tag "Error"
    Stop-Script -ExitCode 1
}

# ========================================================================
#  MODE 1: PACKAGED UNINSTALLER
#  Uses the installer file bundled in the IntuneWin package for uninstall.
#  Registry is still used for post-uninstall validation.
# ========================================================================
if ($usePackagedUninstaller) {

    Write-Log "Configured to use packaged installer for uninstall." -Tag "Info"

    if (-not (Test-Path -Path $installerPath)) {
        Write-Log "Packaged installer not found at path: $installerPath" -Tag "Error"
        Stop-Script -ExitCode 1
    }

    Write-Log "Packaged installer found at path: $installerPath" -Tag "Success"

    $uninstallerCommand = Get-PackagedUninstallerCommand -InstallerPath $installerPath
    if ($null -eq $uninstallerCommand) {
        Stop-Script -ExitCode 1
    }

    $result = Invoke-UninstallWithValidation -FilePath $uninstallerCommand.FilePath `
                                             -ArgumentList $uninstallerCommand.Arguments `
                                             -IsMsi $uninstallerCommand.IsMsi `
                                             -ApplicationName $applicationName `
                                             -RegistryPaths $registrySearchPaths `
                                             -Context "Packaged uninstall" `
                                             -UseWildcardMatching $useWildcardMatching

    Stop-Script -ExitCode $result.ExitCode
}
else {
    # ========================================================================
    #  MODE 2: REGISTRY-BASED UNINSTALL
    #  Searches registry for UninstallString and executes it directly.
    #  Only executes when $usePackagedUninstaller = $false
    # ========================================================================
    Write-Log "Using registry-based uninstall (UninstallString) for '$applicationName'." -Tag "Info"

    $uninstallString = Get-ApplicationUninstallString -ApplicationName $applicationName -RegistryPaths $registrySearchPaths -UseWildcardMatching $useWildcardMatching

    if ($null -eq $uninstallString) {
        Write-Log "Application '$applicationName' not found in registry or UninstallString is missing." -Tag "Error"
        Stop-Script -ExitCode 1
    }

    $uninstallerCommand = Get-ProcessedUninstallerCommand -UninstallString $uninstallString
    if ($null -eq $uninstallerCommand) {
        Stop-Script -ExitCode 1
    }

    $result = Invoke-UninstallWithValidation -FilePath $uninstallerCommand.FilePath `
                                              -ArgumentList $uninstallerCommand.Arguments `
                                              -IsMsi $uninstallerCommand.IsMsi `
                                              -ApplicationName $applicationName `
                                              -RegistryPaths $registrySearchPaths `
                                              -Context "Registry-based uninstall" `
                                              -OriginalUninstallString $uninstallString `
                                              -UseWildcardMatching $useWildcardMatching

    Stop-Script -ExitCode $result.ExitCode
}
