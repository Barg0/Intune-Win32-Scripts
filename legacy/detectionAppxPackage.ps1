# Script version: 2025-05-03 10:45

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Appx Package Name ]---------------------------

# Define the display name of the app you want to check for
$provisionedAppName = "MSTeams"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = 1                         # 1 = Enable logging, 0 = Disable logging
$EnableLogFile = $true           # Set to $false to disable file output

# Application name used for folder/log naming
$applicationName = "Microsoft Teams"

# Define the log output location
$LogFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$applicationName"
$LogFile = "$LogFileDirectory\detection.log"

# Ensure the log directory exists
if (-not (Test-Path $LogFileDirectory)) {
    New-Item -ItemType Directory -Path $LogFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if ($log -ne 1) { return } # Exit if logging is disabled

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "End")
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
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($EnableLogFile) {
        "$logMessage" | Out-File -FilePath $LogFile -Append
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
    Write-Log "======== Detection Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Detection Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ App detection ]---------------------------

# Get the list of provisioned app packages
$provisionedApp = Get-ProvisionedAppxPackage -Online | Where-Object { $_.DisplayName -eq $provisionedAppName }

# Check if the app is found
if ($provisionedApp) {
    Write-Log "Provisioned app detected: $applicationName ($provisionedAppName)" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Provisioned app NOT detected: $applicationName ($provisionedAppName)" -Tag "Error"
    Complete-Script -ExitCode 1
}