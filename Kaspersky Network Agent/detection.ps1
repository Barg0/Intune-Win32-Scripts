# Script version:   2025-05-16 09:40
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$applicationName = "Kaspersky Security Center"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$applicationName"
$logFile = "$logFileDirectory\detection.log"

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
    Write-Log "======== Platform Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# Function to find the latest installed version of a Kaspersky product in the registry
function Get-KasperskyLatestPath {
    param (
        [string]$SearchTerm
    )
    Write-Log "Searching for Kaspersky product: $SearchTerm in the registry..." "Info"

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $latestVersion = "0.0.0.0"
    $latestPath = $null

    foreach ($key in $uninstallKeys) {
        Write-Log "Checking registry path: $key" "Info"
        $subKeys = Get-ChildItem -Path $key -ErrorAction SilentlyContinue
        foreach ($subKey in $subKeys) {
            $displayName = (Get-ItemProperty -Path $subKey.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            $displayVersion = (Get-ItemProperty -Path $subKey.PSPath -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
            $installPath = (Get-ItemProperty -Path $subKey.PSPath -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation

            if ($displayName -and $displayVersion -and $installPath) {
                if ($displayName -match "^$SearchTerm") {
                    Write-Log "Found $displayName (Version: $displayVersion) at $installPath" "Info"
                    if ([version]$displayVersion -gt [version]$latestVersion) {
                        $latestVersion = $displayVersion
                        $latestPath = $installPath
                    }
                }
            }
        }
    }
    if ($latestPath) {
        Write-Log "Latest version found: $latestVersion at $latestPath" "Success"
    } else {
        Write-Log "No matching registry entry found for: $SearchTerm" "Error"
    }
    return $latestPath
}

# Detect Kaspersky Network Agent
Write-Log "Detecting Kaspersky Network Agent in registry..." "Info"
$KasperskyAgentPath = Get-KasperskyLatestPath -SearchTerm $applicationName

# Validate detected registry paths
if ($KasperskyAgentPath) {
    Write-Log "Kaspersky Network Agent is installed at: $KasperskyAgentPath" "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Kaspersky Network Agent is NOT installed or registry entry is missing." "Error"
    Complete-Script -ExitCode 1
}