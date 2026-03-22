# Script version:   2025-06-20 21:15
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Application name ]---------------------------

$applicationName = "VMware Workstation Pro"

# ---------------------------[ Log name ]---------------------------

$logFileName = "uninstall.log"

# ---------------------------[ Installer ]---------------------------

$installerName = "VMware-workstation-full-17.6.3-24583834.exe"
$installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$applicationName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if logging is disabled

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "  # Fallback if an unrecognized tag is used
    }

    # Set tag colors
    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Check"   { "Blue" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow"}
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    # Write to console with color formatting
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
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ Uninstall ]---------------------------

Write-Log "Looking for uninstaller at: $installerPath" -Tag "Check"

if (-not (Test-Path -Path $installerPath)) {
    Write-Log "Uninstaller not found: $installerPath" -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Starting silent uninstall..." -Tag "Info"

try {
    $arguments = '/s /v"/qn REMOVE=ALL"'
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    Write-Log "Uninstaller exited with code: $($process.ExitCode)" -Tag "Info"

    if ($process.ExitCode -eq 0) {
        Write-Log "$applicationName uninstalled successfully." -Tag "Success"
        Complete-Script -ExitCode 0
    } else {
        Write-Log "Uninstaller returned a non-zero exit code." -Tag "Error"
        Complete-Script -ExitCode 1
    }
}
catch {
    Write-Log "Exception during uninstallation: $_" -Tag "Error"
    Complete-Script -ExitCode 1
}