# ====================[ Script Start Timestamp ]===================
# Capture start time to log script duration
$scriptStartTime = Get-Date

# ===========================[ CONFIG ]===========================
# ---- Application Shortcut Details ----
$linkName      = "Shared App"                                   # Shortcut display name (no extension)
$targetPath    = "\\app1.domain.local\Program\Start.exe"        # UNC path to the executable
$arguments     = ""                                             # Optional: command-line arguments
$startIn       = ""                                             # Optional: working directory (blank = omit)

# =========================[ Script name ]=========================

# Script name used for folder/log naming
$scriptName = "Shortcut - $linkName"
$logFileName = "install.log"

# =========================[ Logging Setup ]=======================

# Logging control switches
$log = $true                     # Set to $false to disable all logging
$enableLogFile = $true           # Set to $false to disable file output
$logDebug = $false               # Set to $true to allow debug logs

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    [CmdletBinding()]
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }                       # All logging off
    if ($Tag -eq "Debug" -and -not $logDebug) { return }  # Suppress debug

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()
    if ($tagList -contains $rawTag) { $rawTag = $rawTag.PadRight(7) } else { $rawTag = "Error  " }

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
    if ($enableLogFile) { "$logMessage" | Out-File -FilePath $logFile -Append }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

# ---------------------------[ Exit Function ]---------------------------

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

# =========================[ Derived Paths ]=======================

$shortcutFileName = "$linkName.lnk"
$desktopPath      = [Environment]::GetFolderPath('Desktop')
$startMenuPath    = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs"

$desktopShortcutPath   = Join-Path -Path $desktopPath   -ChildPath $shortcutFileName
$startMenuShortcutPath = Join-Path -Path $startMenuPath -ChildPath $shortcutFileName

# =========================[ Helper Functions ]====================

function New-ShortcutFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory
    )
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($ShortcutPath)
        $sc.TargetPath = $TargetPath
        if ($Arguments) { $sc.Arguments = $Arguments }
        if ($WorkingDirectory) { $sc.WorkingDirectory = $WorkingDirectory }
        $sc.Save()
        Write-Log "Shortcut created: $ShortcutPath -> $TargetPath" -Tag "Success"
    } catch {
        Write-Log "Failed to create shortcut '$ShortcutPath'. $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

function Get-ShortcutTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ShortcutPath)
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($ShortcutPath)
        return $sc.TargetPath
    } catch {
        Write-Log "Failed to read shortcut '$ShortcutPath'. $_" -Tag "Error"
        return $null
    }
}

function Test-ShortcutExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ShortcutPath)

    if (Test-Path -Path $ShortcutPath) {
        Write-Log "Found shortcut: $ShortcutPath" -Tag "Success"
        return $true
    } else {
        Write-Log "Missing shortcut: $ShortcutPath" -Tag "Error"
        return $false
    }
}

# ===========================[ Script Start ]======================

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $scriptName" -Tag "Info"
Write-Log "Target: $targetPath | Args: '$arguments' | StartIn: '$startIn'" -Tag "Debug"

# Create Desktop and Start Menu shortcuts
Write-Log "Creating Desktop shortcut: $desktopShortcutPath" -Tag "Debug"
New-ShortcutFile -ShortcutPath $desktopShortcutPath -TargetPath $targetPath -Arguments $arguments -WorkingDirectory $startIn

Write-Log "Creating Start Menu shortcut: $startMenuShortcutPath" -Tag "Debug"
New-ShortcutFile -ShortcutPath $startMenuShortcutPath -TargetPath $targetPath -Arguments $arguments -WorkingDirectory $startIn

# Verify creation + target
$desktopOk = Test-ShortcutExists -ShortcutPath $desktopShortcutPath
$startOk   = Test-ShortcutExists -ShortcutPath $startMenuShortcutPath

$desktopTargetOk = $false
$startTargetOk   = $false
if ($desktopOk) { $desktopTargetOk = (Get-ShortcutTarget -ShortcutPath $desktopShortcutPath) -eq $targetPath }
if ($startOk)   { $startTargetOk   = (Get-ShortcutTarget -ShortcutPath $startMenuShortcutPath)   -eq $targetPath }

if ($desktopOk -and $startOk -and $desktopTargetOk -and $startTargetOk) {
    Write-Log "All shortcuts created and target path verified." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Shortcut creation or target verification failed." -Tag "Error"
    Complete-Script -ExitCode 1
}