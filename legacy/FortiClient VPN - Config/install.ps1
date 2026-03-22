# Script version:   2025-08-01 11:30
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Parameter ]---------------------------

# FortiClient Config
$fortiConfigName = "example.conf"
$fortiConfigPassword = "putYourPasswordHere"

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$applicationName = "FortiClient VPN - Config"
$logFileName = "install.log"

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

# Define temporary directory
$tempDir = "C:\vpnImportFolderTemp"
if (-not (Test-Path $tempDir)) {
    Write-Log "Temporary directory not found. Creating: $tempDir" -Tag "Info"
    New-Item -Path $tempDir -ItemType Directory | Out-Null
}

# Search for FCConfig.exe in possible locations
$fcPaths = @(
    "C:\Program Files\Fortinet\FortiClient\FCConfig.exe",
    "C:\Program Files (x86)\Fortinet\FortiClient\FCConfig.exe"
)

$fcConfigPath = $null
foreach ($path in $fcPaths) {
    if (Test-Path $path) {
        $fcConfigPath = $path
        break
    }
}

if (-not $fcConfigPath) {
    Write-Log "FCConfig.exe not found. Installation cannot proceed." -Tag "Error"
    exit 1  # Exit with error code for Intune
}

Write-Log "FCConfig.exe found at: $fcConfigPath" -Tag "Success"

# Define config file path
$sourceConfigFile = Join-Path -Path $PSScriptRoot -ChildPath $fortiConfigName
$destinationConfigFile = "$tempDir\$fortiConfigName"
Write-Log "FortClient VPN - Config location: $($sourceConfigFile)" -Tag "Debug"

if (-not (Test-Path $sourceConfigFile)) {
    Write-Log "Configuration file not found: $sourceConfigFile" -Tag "Error"
    Complete-Script -ExitCode 1
}

# Copy config file to temp directory
Write-Log "Copying configuration file to temporary directory." -Tag "Info"
Copy-Item -Path $sourceConfigFile -Destination $destinationConfigFile -Force

Write-Log "Importing configuration..." -Tag "Start"

# Import configuration
$command = "& '$fcConfigPath' -m all -f '$destinationConfigFile' -o import -i 1 -p $fortiConfigPassword"
Invoke-Expression $command
if ($?) {
    Write-Log "Configuration import successful." -Tag "Success"
} else {
    Write-Log "Configuration import failed." -Tag "Error"
    Complete-Script -ExitCode 1
}

# Remove temporary directory
Write-Log "Removing temporary directory: $tempDir" -Tag "Info"
Remove-Item -Path $tempDir -Recurse -Force

Complete-Script -ExitCode 0
