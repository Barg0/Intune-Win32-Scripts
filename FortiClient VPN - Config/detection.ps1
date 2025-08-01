# Script version:   2025-08-01 11:30
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Parameter ]---------------------------

# FortiClient Config Names to check
$fortiConfigNames = @(
    "FIRST VPN",
    "SECOND VPN"
)

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$applicationName = "FortiClient VPN - Config"
$logFileName = "detection.log"

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

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# Registry root paths to check (IPSec and SSLVPN)
$regBasePaths = @(
    "HKLM:\SOFTWARE\Fortinet\FortiClient\IPSec\Tunnels",
    "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"
)

# Track configs that are missing in both locations
$missingConfigs = @()

foreach ($name in $fortiConfigNames) {
    $found = $false

    foreach ($base in $regBasePaths) {
        $regPath = Join-Path $base $name
        Write-Log "Checking for registry path: $regPath" -Tag "Check"

        if (Test-Path $regPath) {
            Write-Log "Registry path found for config: $name in $base" -Tag "Success"
            $found = $true
            break
        }
    }

    if (-not $found) {
        Write-Log "Config '$name' not found in any known VPN registry paths." -Tag "Error"
        $missingConfigs += $name
    }
}

if ($missingConfigs.Count -gt 0) {
    Write-Log "Missing VPN configs: $($missingConfigs -join ', ')" -Tag "Error"
    Complete-Script -ExitCode 1
} else {
    Write-Log "All VPN configs were found in registry." -Tag "Success"
    Complete-Script -ExitCode 0
}