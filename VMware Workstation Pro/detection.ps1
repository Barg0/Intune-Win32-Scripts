# Script Version: 2025-06-20 21:30
# Script Author: Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Registry Values ]---------------------------

$softwareName = "VMware Workstation"
$softwareVersion = "17.6.3"

# ---------------------------[ Registry Paths ]---------------------------

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Log name ]---------------------------

$applicationName = "VMware Workstation Pro"
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
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ Detection Logic ]---------------------------

# Flag to indicate if the program is found
$programFound = $false

Write-Log "Checking registry for software: $softwareName Version: $softwareVersion" "Check"

# Iterate over each registry path
foreach ($registryPath in $registryPaths) {
    if (-not (Test-Path $registryPath)) {
        Write-Log "Registry path $registryPath does not exist, skipping." "Info"
        continue
    }

    $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue

    foreach ($subkey in $subkeys) {
        $displayName = (Get-ItemProperty -Path $subkey.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
        $displayVersion = (Get-ItemProperty -Path $subkey.PSPath -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion

        if ($displayName -eq $softwareName -and $displayVersion -eq $softwareVersion) {
            Write-Log "Found installed software: $displayName ($displayVersion)" "Success"
            $programFound = $true
            break
        }
    }

    if ($programFound) { break }
}

# ---------------------------[ Script End ]---------------------------

if ($programFound) {
    Write-Log "$softwareName Version $softwareVersion is installed." "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "$softwareName Version $softwareVersion is not installed." "Error"
    Complete-Script -ExitCode 1
}