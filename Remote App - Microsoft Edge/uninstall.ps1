# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "uninstall.log"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$($env:USERNAME)\$applicationName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "
    }

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

function Complete-Script {
    param([int]$ExitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ Variables ]---------------------------
$LocalFolderName          = "RemoteDesktopApps"
$RdpFileName              = "MicrosoftEdge.rdp"
$IconFileName             = "MicrosoftEdge.ico"
$DesktopShortcutName      = "Microsoft Edge (RDP)"   # Without .lnk
$StartMenuShortcutName    = "Microsoft Edge (RDP)"   # Without .lnk

$TargetFolderPath         = Join-Path -Path $env:LocalAppData -ChildPath $LocalFolderName
$TargetRdpPath            = Join-Path -Path $TargetFolderPath -ChildPath $RdpFileName
$TargetIconPath           = Join-Path -Path $TargetFolderPath -ChildPath $IconFileName

$DesktopPath              = [Environment]::GetFolderPath("Desktop")
$DesktopShortcutPath      = Join-Path -Path $DesktopPath -ChildPath ($DesktopShortcutName + ".lnk")

$StartMenuRoot            = [Environment]::GetFolderPath("StartMenu")
$StartMenuPrograms        = Join-Path -Path $StartMenuRoot -ChildPath "Programs"
$StartMenuShortcutPath    = Join-Path -Path $StartMenuPrograms -ChildPath ($StartMenuShortcutName + ".lnk")

# ---------------------------[ Removal Steps ]---------------------------

# 1) Remove Desktop Shortcut
Write-Log "Checking for desktop shortcut: $DesktopShortcutPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $DesktopShortcutPath) {
        Write-Log "Shortcut found. Deleting: $DesktopShortcutPath" -Tag "Info"
        Remove-Item -LiteralPath $DesktopShortcutPath -Force
        Write-Log "Desktop shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Desktop shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove desktop shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 2) Remove Start Menu Shortcut
Write-Log "Checking for Start Menu shortcut: $StartMenuShortcutPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $StartMenuShortcutPath) {
        Write-Log "Shortcut found. Deleting: $StartMenuShortcutPath" -Tag "Info"
        Remove-Item -LiteralPath $StartMenuShortcutPath -Force
        Write-Log "Start Menu shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Start Menu shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove Start Menu shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 3) Remove RDP file
Write-Log "Checking for RDP file: $TargetRdpPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $TargetRdpPath) {
        Write-Log "RDP file found. Deleting: $TargetRdpPath" -Tag "Info"
        Remove-Item -LiteralPath $TargetRdpPath -Force
        Write-Log "RDP file deleted." -Tag "Success"
    } else {
        Write-Log "RDP file not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove RDP file. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 4) Remove Icon file
Write-Log "Checking for icon file: $TargetIconPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $TargetIconPath) {
        Write-Log "Icon file found. Deleting: $TargetIconPath" -Tag "Info"
        Remove-Item -LiteralPath $TargetIconPath -Force
        Write-Log "Icon file deleted." -Tag "Success"
    } else {
        Write-Log "Icon file not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove icon file. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Uninstall cleanup complete." -Tag "Success"
Complete-Script -ExitCode 0