# Script version:   2025-08-01 11:30
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Parameter ]---------------------------

# FortiClient Config Names to remove
$fortiConfigNames = @(
    "FIRST VPN",
    "SECOND VPN"
)

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$applicationName = "FortiClient VPN - Config"
$logFileName = "uninstall.log"

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

# Registry root paths to remove from (IPSec and SSLVPN)
$regBasePaths = @(
    "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels",
    "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"
)

# Track configs that could not be deleted
$failedConfigs = @()

foreach ($name in $fortiConfigNames) {
    $success = $false

    foreach ($base in $regBasePaths) {
        $regPath = Join-Path $base $name
        Write-Log "Attempting to remove registry key: $regPath" -Tag "Check"

        if (Test-Path $regPath) {
            try {
                Remove-Item -Path $regPath -Recurse -Force
                Write-Log "Successfully removed: $regPath" -Tag "Success"
                $success = $true
            } catch {
                Write-Log "ERROR: Failed to remove $regPath - $_" -Tag "Error"
            }
        } else {
            Write-Log "Registry key not found: $regPath" -Tag "Info"
        }
    }

    if (-not $success) {
        $failedConfigs += $name
    }
}

if ($failedConfigs.Count -gt 0) {
    Write-Log "Some configs could not be removed: $($failedConfigs -join ', ')" -Tag "Error"
    Complete-Script -ExitCode 1
} else {
    Write-Log "All VPN configs removed successfully." -Tag "Success"
    Complete-Script -ExitCode 0
}