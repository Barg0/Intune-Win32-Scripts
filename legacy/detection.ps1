# Script Version: 2025-05-04 18:05

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Software Values ]---------------------------

$softwareName = "Nilesoft Shell"
$softwareVersion = "1.9.18"

# ---------------------------[ Registry Paths ]---------------------------

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = 1                         # 1 = Enable logging, 0 = Disable logging
$EnableLogFile = $true           # Set to $false to disable file output

# Application name used for folder/log naming
$applicationName = "Nilesoft Shell"

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
    Write-Log "========== Detection Script Completed ==========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Execution ]---------------------------

Write-Log "========== Starting Detection Script ==========" "Start"
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