# ====================[ Script Start Timestamp ]===================

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ===========================[ CONFIG ]===========================
# ---- Detection behavior ----
$validateDesktopShortcut = $true             # Set to $false to skip Desktop shortcut validation

# ---- Web link details (should match install config) ----
$linkName         = "Google"                # Shortcut display name (no extension)
$iconFileName     = "Google.ico"            # Icon file name used by the install

# ---- Folder/paths (should match install config) ----
$appFolderName    = "WebLinkIcons"         # Folder in %LOCALAPPDATA%

# ---- Derived paths ----
$shortcutFileName = "$linkName.url"
$localAppDataPath = $env:LOCALAPPDATA
$destinationFolder = Join-Path -Path $localAppDataPath -ChildPath $appFolderName
$iconPath         = Join-Path -Path $destinationFolder -ChildPath $iconFileName

$desktopPath      = [Environment]::GetFolderPath('Desktop')
$startMenuPath    = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs"

$desktopShortcutPath   = Join-Path -Path $desktopPath   -ChildPath $shortcutFileName
$startMenuShortcutPath = Join-Path -Path $startMenuPath -ChildPath $shortcutFileName

# =========================[ Script name ]=========================

# Script name used for folder/log naming
$scriptName = "WebLink - $linkName"
$logFileName = "detection.log"

# =========================[ Logging Setup ]=======================

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output
$logDebug = $false               # Set to $true to allow debug logs

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$($env:USERNAME)\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
# Function to write structured logs to file and console
function Write-Log {
    [CmdletBinding()]
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if all logging disabled

    # Handle debug suppression
    if ($Tag -eq "Debug" -and -not $logDebug) { return }

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
        "Debug"   { "DarkYellow" }
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

# =========================[ Exit Function ]=======================

function Complete-Script {
    [CmdletBinding()]
    param([int]$ExitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# =========================[ Helper Functions ]====================

function Test-ItemPresent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -Path $Path) {
        Write-Log "Found: $Path" -Tag "Success"
        return $true
    } else {
        Write-Log "Missing: $Path" -Tag "Error"
        return $false
    }
}

# ===========================[ Script Start ]======================

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $scriptName" -Tag "Info"

# 1) Check icon file presence
Write-Log "Checking icon file: $iconPath" -Tag "Debug"
$iconOk = Test-ItemPresent -Path $iconPath

# 2) Check shortcuts presence (Start Menu always; Desktop optional)
Write-Log "Checking Start Menu shortcut: $startMenuShortcutPath" -Tag "Debug"
$startOk = Test-ItemPresent -Path $startMenuShortcutPath

$desktopOk = $true
if ($validateDesktopShortcut) {
    Write-Log "Checking Desktop shortcut (validation enabled): $desktopShortcutPath" -Tag "Debug"
    $desktopOk = Test-ItemPresent -Path $desktopShortcutPath
} else {
    Write-Log "Desktop shortcut validation disabled by config." -Tag "Info"
}

# 3) Exit appropriately (0 = installed; 1 = not installed)
if ($iconOk -and $startOk -and $desktopOk) {
    Write-Log "All required components detected." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Detection failed: one or more components are missing." -Tag "Error"
    Complete-Script -ExitCode 1
}
