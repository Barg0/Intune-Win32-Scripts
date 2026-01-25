# ===========================[ Script Start Timestamp ]===========================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]===================================

# Script / application metadata
$applicationName  = "__REGISTRY_DISPLAY_NAME__"

# Installer configuration
$installerName        = "setup.exe"
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# EXE installer arguments
$installerArgumentsExe = '/silent'

# Registry paths to search for the installed application
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ===========================[ Logging Configuration ]=====================
$scriptName       = $applicationName
$logFileName      = "install.log"

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
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ===========================[ Logging Function ]================================
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches
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
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        }
        catch {
            # Logging must never block script execution
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

# ===========================[ Detection Function ]=============================
function Test-ApplicationInstalled {
    [CmdletBinding()]
    param(
        [string]$ApplicationName,
        [string[]]$RegistryPaths
    )

    Write-Log "Checking registry for application '$ApplicationName'." -Tag "Get"

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

            if ($displayName -eq $ApplicationName) {
                Write-Log "Match found for application: '$displayName'" -Tag "Success"
                return $true
            }
        }
    }

    return $false
}

# ===========================[ Script Start ]====================================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

Write-Log "Script configuration - InstallerName: '$installerName'" -Tag "Debug"
Write-Log "Script configuration - InstallerPath: '$installerPath'" -Tag "Debug"
Write-Log "Script configuration - LogFile: '$logFile'" -Tag "Debug"

# ===========================[ Installer Detection ]=============================
Write-Log "Validating installer path..." -Tag "Get"

if (-not (Test-Path -Path $installerPath)) {
    Write-Log "Installer not found at path: $installerPath" -Tag "Error"
    Stop-Script -ExitCode 1
}

Write-Log "Installer found at path: $installerPath" -Tag "Success"

# ===========================[ Install ]=========================================
Write-Log "Starting installation for '$applicationName'." -Tag "Run"

try {
    Write-Log "Launching process: '$installerPath' with arguments: $installerArgumentsExe" -Tag "Debug"

    # Use -PassThru to capture the process object for verification
    # This allows us to confirm the installer process started successfully
    $process = Start-Process -FilePath $installerPath -ArgumentList $installerArgumentsExe -Wait -PassThru -NoNewWindow

    if ($null -eq $process) {
        Write-Log "Start-Process did not return a process object. Installation may have failed to start." -Tag "Error"
    }

    Write-Log "Installer process ID: $($process.Id)" -Tag "Debug"
    Write-Log "Installer process has completed. Verifying installation via registry detection..." -Tag "Info"
}
catch {
    Write-Log "Exception during installation: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
    Stop-Script -ExitCode 1
}

# ===========================[ Installation Verification ]=======================
Write-Log "Waiting for registry keys to be populated..." -Tag "Info"

# Some installers may take a moment to write registry keys after process exit
# Retry detection with a short delay to account for this
$maxRetries = 3
$retryDelay = 5
$applicationFound = $false

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    if ($attempt -gt 1) {
        Write-Log "Retry attempt $attempt of $maxRetries after $retryDelay seconds..." -Tag "Info"
        Start-Sleep -Seconds $retryDelay
    }

    $applicationFound = Test-ApplicationInstalled -ApplicationName $applicationName -RegistryPaths $registrySearchPaths

    if ($applicationFound) {
        Write-Log "$applicationName is installed and verified in registry." -Tag "Success"
        Stop-Script -ExitCode 0
    }
}

if (-not $applicationFound) {
    Write-Log "$applicationName was not found in registry after $maxRetries attempts. Installation may have failed." -Tag "Error"
    Stop-Script -ExitCode 1
}
