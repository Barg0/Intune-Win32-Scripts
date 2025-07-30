# Script version:   2025-07-30 20:30
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Parameter ]---------------------------

$imageFiles = @(
    "6a79fc99-ea63-4b13-87ab-99f4135ca8f9Company.jpg", 
    "6a79fc99-ea63-4b13-87ab-99f4135ca8f9Company_thumb.jpg"
    )

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Teams Background"
$logFileName = "install.log"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$env:USERNAME\$scriptName"
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
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"


# ---------------------------[ Execution ]---------------------------

function Test-TeamsPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            Write-Log "Path does not exist: $Path. Creating..." -Tag "Info"
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Path created successfully: $Path" -Tag "Success"
        } else {
            Write-Log "Path already exists: $Path" -Tag "Check"
        }
    } catch {
        Write-Log "Failed to verify or create path '$Path': $($_.Exception.Message)" -Tag "Error"
        throw
    }
}

foreach ($imageFile in $imageFiles) {
    try {
        $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $imageFile
        $destinationPath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Backgrounds\Uploads"
        Test-TeamsPath -Path $destinationPath

        Write-Log "Copying $imageFile to Teams upload folder..." -Tag "Info"
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force -ErrorAction Stop

        $copiedPath = Join-Path -Path $destinationPath -ChildPath $imageFile
        if (Test-Path $copiedPath) {
            Write-Log "$($imageFile) copied successfully." -Tag "Success"
        } else {
            Write-Log "$($imageFile) did not appear at destination after copy." -Tag "Error"
            $failure = $true
        }
    } catch {
        Write-Log "Exception while copying $($imageFile): $($_.Exception.Message)" -Tag "Error"
        $failure = $true
    }
}

if ($failure) {
    Complete-Script -ExitCode 1
} else {
    Complete-Script -ExitCode 0
}

