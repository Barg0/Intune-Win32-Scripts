# ===========================[ Script Start Timestamp ]===========================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]===================================

# Application metadata (used for logging and registry detection)
$applicationName  = "Global Secure Access Client"

# Installer configuration
# MSI installer file name (must be included in the IntuneWin package)
$installerName        = "GlobalSecureAccessClient.msi"
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# MSI installer arguments
# The /i switch and installer path are automatically prepended by Get-MsiInstallArguments function
# Add all additional MSI arguments here (e.g., /qn, /norestart, TRANSFORMS, PROPERTIES, etc.)
# Common arguments:
#   /qn = quiet mode (no UI)
#   /norestart = suppress automatic reboot
#   /l*v = verbose logging to file
#   TRANSFORMS=file.mst = apply transform file
#   PROPERTY=Value = set MSI property
# Examples: "/qn /norestart", "/qn /norestart /l*v C:\Logs\install.log", "/qn TRANSFORMS=transform.mst PROPERTY=Value"
$installerArguments = "/qn /norestart"

# Registry paths to search for the installed application
# Used for post-installation verification
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ===========================[ Logging Configuration ]=====================
$scriptName       = $applicationName
$logFileName      = "install.log"

# Logging configuration
$log           = $true    # Master switch for all logging
$logDebug      = $false   # Set to $true to show DEBUG logs
$logGet        = $true    # Enable/disable all [Get] logs (registry searches)
$logRun        = $true    # Enable/disable all [Run] logs (process execution)
$enableLogFile = $true    # Enable/disable file logging

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

# Ensure log directory exists
# If directory creation fails, script continues (logging to file will fail silently)
if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    try {
        $null = New-Item -ItemType Directory -Path $logFileDirectory -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to create log directory '$logFileDirectory': $($_.Exception.Message)"
        # Continue execution - logging will fail but script should continue
    }
}

# ===========================[ Logging Function ]================================
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    # Master logging switch
    if (-not $log) { return }

    # Per-tag logging switches (allows granular control of log verbosity)
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
        # If an unknown tag is used, treat it as Error to keep things strict
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
            # Logging must never block script execution - silently fail if log file is locked or inaccessible
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ===========================[ Exit Function ]===================================
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

# ===========================[ Execute Install Process Function ]===============
function Invoke-InstallProcess {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$Context = "Install"
    )

    # Validate FilePath
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        Write-Log "FilePath is empty or null. Cannot start $Context process." -Tag "Error"
        return $null
    }

    Write-Log "Starting $Context process: '$FilePath' $ArgumentList" -Tag "Run"

    try {
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
    }
    catch {
        Write-Log "$Context process failed to start: $($_.Exception.Message)" -Tag "Error"
        Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        return $null
    }

    Write-Log "$Context process ID: $($process.Id)" -Tag "Debug"
    Write-Log "$Context exit code: $($process.ExitCode)" -Tag "Info"

    return $process
}

# ===========================[ Installation Verification Function ]==============
function Test-InstallationVerification {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    Write-Log "Waiting for registry keys to be populated..." -Tag "Info"

    # Some installers may take a moment to write registry keys after process exit
    # Retry detection with delays to account for registry write delays
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "Retry attempt $attempt of $MaxRetries after $RetryDelay seconds..." -Tag "Info"
            Start-Sleep -Seconds $RetryDelay
        }

        try {
            $applicationFound = Test-ApplicationInstalled -ApplicationName $ApplicationName -RegistryPaths $RegistryPaths

            if ($applicationFound) {
                Write-Log "$ApplicationName is installed and verified in registry." -Tag "Success"
                return $true
            }
        }
        catch {
            Write-Log "Exception during verification attempt $attempt: $($_.Exception.Message)" -Tag "Error"
            Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
            # Continue to next retry attempt
        }
    }

    Write-Log "$ApplicationName was not found in registry after $MaxRetries attempts. Installation may have failed." -Tag "Error"
    return $false
}

# ===========================[ Parse MSI Arguments Function ]===================
function Get-MsiInstallArguments {
    [CmdletBinding()]
    param(
        [string]$InstallerPath,
        [string]$Arguments
    )

    # Validate InstallerPath is provided
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        Write-Log "InstallerPath is empty or null. Cannot construct MSI arguments." -Tag "Error"
        return $null
    }

    # Escape quotes in path if present (double them), then quote the entire path
    # This handles paths like: C:\Program Files\App\installer.msi
    $escapedPath = $InstallerPath -replace '"', '""'
    
    # Start with /i (install) and the quoted installer path (required for msiexec)
    $fullArguments = "/i `"$escapedPath`""
    
    # Add user-provided additional arguments if provided
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $argsTrimmed = $Arguments.Trim()
        
        # Validate arguments don't conflict with required /i switch
        # /i and /package are automatically added, so warn if user tries to add them
        if ($argsTrimmed -match '/(?:i|package)') {
            Write-Log "Warning: Arguments contain /i or /package which conflicts with required installer path argument." -Tag "Info"
        }
        
        $fullArguments += " $argsTrimmed"
    }
    
    return $fullArguments
}

# ===========================[ Detection Function ]=============================
function Test-ApplicationInstalled {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths
    )

    Write-Log "Checking registry for application '$ApplicationName'." -Tag "Get"

    # Search through all specified registry paths
    foreach ($registryPath in $RegistryPaths) {
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

        # Check each subkey for matching DisplayName
        foreach ($subKey in $subKeys) {
            $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) {
                Write-Log "Could not read properties for key: $($subKey.PSPath)" -Tag "Debug"
                continue
            }

            $displayName = $properties.DisplayName

            if ($displayName) {
                Write-Log "Found product: '$displayName'" -Tag "Debug"
            }

            # Match found - application is installed
            if ($displayName -eq $ApplicationName) {
                Write-Log "Match found for application: '$displayName'" -Tag "Success"
                return $true
            }
        }
    }

    # No match found in any registry path
    return $false
}

# ===========================[ Script Start ]====================================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

# Validate application name is configured
if ([string]::IsNullOrWhiteSpace($applicationName)) {
    Write-Log "Application name is not configured. Please set `$applicationName." -Tag "Error"
    Stop-Script -ExitCode 1
}

Write-Log "Script configuration - InstallerName: '$installerName'" -Tag "Debug"
Write-Log "Script configuration - InstallerPath: '$installerPath'" -Tag "Debug"
Write-Log "Script configuration - LogFile: '$logFile'" -Tag "Debug"

# ===========================[ Installer Detection ]=============================
# Validate that the MSI installer file exists before attempting installation
Write-Log "Validating installer path..." -Tag "Get"

if (-not (Test-Path -Path $installerPath)) {
    Write-Log "Installer not found at path: $installerPath" -Tag "Error"
    Stop-Script -ExitCode 1
}

Write-Log "Installer found at path: $installerPath" -Tag "Success"

# ===========================[ Install ]=========================================
# Execute MSI installation via msiexec.exe
Write-Log "Starting installation for '$applicationName'." -Tag "Run"

# Initialize process exit code variable (used after try-catch block)
$processExitCode = $null

try {
    # Construct complete MSI arguments with installer path and user-provided arguments
    # The function automatically prepends /i and the quoted installer path
    $msiArguments = Get-MsiInstallArguments -InstallerPath $installerPath `
                                             -Arguments $installerArguments
    
    # Validate arguments were constructed successfully
    if ($null -eq $msiArguments) {
        Write-Log "Failed to construct MSI arguments. Installation cannot proceed." -Tag "Error"
        Stop-Script -ExitCode 1
    }
    
    Write-Log "Launching MSI installation via msiexec.exe with arguments: $msiArguments" -Tag "Debug"

    # Execute the MSI installation process
    # MSI exit codes: 0 = success, 3010 = success but reboot required, other = varies by installer
    $process = Invoke-InstallProcess -FilePath "msiexec.exe" `
                                      -ArgumentList $msiArguments `
                                      -Context "MSI installation"

    # Handle process execution result
    # Continue to verification as registry check is the source of truth
    if ($null -ne $process) {
        $processExitCode = $process.ExitCode

        # Evaluate exit code for logging purposes
        # Note: Verification is the ultimate source of truth, not exit codes
        if ($process.ExitCode -eq 0) {
            Write-Log "MSI installation completed successfully." -Tag "Success"
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "MSI installation completed successfully but reboot is required (exit code 3010)." -Tag "Info"
        }
        else {
            Write-Log "MSI installation returned exit code: $($process.ExitCode)" -Tag "Info"
            # Continue to verification - some MSI installers return non-zero codes even on success
        }
    }
    else {
        Write-Log "Continuing to verification - installation may have succeeded despite process object being null." -Tag "Info"
    }

    Write-Log "MSI installer process has completed. Verifying installation via registry detection..." -Tag "Info"
}
catch {
    Write-Log "Exception during installation: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
    Stop-Script -ExitCode 1
}

# ===========================[ Installation Verification ]=======================
# Verify installation by checking registry for the application
$verificationSuccess = Test-InstallationVerification -ApplicationName $applicationName `
                                                      -RegistryPaths $registrySearchPaths

if ($verificationSuccess) {
    # Pass the original exit code to Stop-Script (Intune will interpret it)
    # Exit codes 0 and 3010 are standard MSI success codes
    # If process was null but verification passed, use 0 (success) since verification is the source of truth
    $exitCode = if ($null -ne $processExitCode) { $processExitCode } else { 0 }
    Stop-Script -ExitCode $exitCode
}
else {
    # Verification failure takes precedence over exit codes
    # Return error code 1 to indicate installation verification failed
    # Intune can be configured to interpret MSI exit codes, but verification failure is definitive
    Stop-Script -ExitCode 1
}
