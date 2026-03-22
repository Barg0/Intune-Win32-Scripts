# ====================[ Script Start Timestamp ]===================
# Capture start time to log script duration
$scriptStartTime = Get-Date

# ===========================[ CONFIG ]===========================
# ---- Application Shortcut Details (must match install) ----
$linkName   = "Shared App"                                   # Shortcut display name (no extension)

# =========================[ Script name ]=========================

$scriptName = "Shortcut - $linkName"
$logFileName = "uninstall.log"

# =========================[ Logging Setup ]=======================

$log = $true
$enableLogFile = $true
$logDebug = $false

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param ([string]$Message, [string]$Tag = "Info")
    if (-not $log) { return }
    if ($Tag -eq "Debug" -and -not $logDebug) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start","Check","Info","Success","Error","Debug","End")
    $rawTag = ($Tag.Trim()); if ($tagList -contains $rawTag) { $rawTag = $rawTag.PadRight(7) } else { $rawTag = "Error  " }
    $color = switch ($rawTag.Trim()) { "Start"{"Cyan"}"Check"{"Blue"}"Info"{"Yellow"}"Success"{"Green"}"Error"{"Red"}"Debug"{"DarkYellow"}"End"{"Cyan"} default{"White"} }
    $logMessage = "$timestamp [  $rawTag ] $Message"
    if ($enableLogFile) { "$logMessage" | Out-File -FilePath $logFile -Append }
    Write-Host "$timestamp " -NoNewline; Write-Host "[  " -NoNewline -ForegroundColor White; Write-Host "$rawTag" -NoNewline -ForegroundColor $color; Write-Host " ] " -NoNewline -ForegroundColor White; Write-Host "$Message"
}

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

function Remove-ItemIfExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -Path $Path) {
        try {
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Write-Log "Removed: $Path" -Tag "Success"
            return $true
        } catch {
            Write-Log "Failed to remove '$Path'. $_" -Tag "Error"
            return $false
        }
    } else {
        Write-Log "Already absent: $Path" -Tag "Info"
        return $true
    }
}

function Test-ItemAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -Path $Path)) { Write-Log "Verified absent: $Path" -Tag "Success"; return $true }
    else { Write-Log "Still present: $Path" -Tag "Error"; return $false }
}

# ===========================[ Script Start ]======================

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

Write-Log "Removing Desktop shortcut: $desktopShortcutPath" -Tag "Debug"
$desktopRemoved = Remove-ItemIfExists -Path $desktopShortcutPath

Write-Log "Removing Start Menu shortcut: $startMenuShortcutPath" -Tag "Debug"
$startRemoved = Remove-ItemIfExists -Path $startMenuShortcutPath

$desktopAbsent = Test-ItemAbsent -Path $desktopShortcutPath
$startAbsent   = Test-ItemAbsent -Path $startMenuShortcutPath

if ($desktopRemoved -and $startRemoved -and $desktopAbsent -and $startAbsent) {
    Write-Log "All shortcuts removed successfully." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "One or more shortcuts failed to remove." -Tag "Error"
    Complete-Script -ExitCode 1
}