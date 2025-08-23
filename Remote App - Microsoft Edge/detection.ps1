# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "detection.log"

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
$LocalFolderName = "RemoteDesktopApps"
$RdpFileName     = "MicrosoftEdge.rdp"
$IconFileName    = "icon.ico"
$ShortcutName    = "Microsoft Edge (RDP)"

$TargetFolderPath = Join-Path -Path $env:LocalAppData -ChildPath $LocalFolderName
$TargetRdpPath    = Join-Path -Path $TargetFolderPath -ChildPath $RdpFileName
$TargetIconPath   = Join-Path -Path $TargetFolderPath -ChildPath $IconFileName
$DesktopPath      = [Environment]::GetFolderPath("Desktop")
$ShortcutPath     = Join-Path -Path $DesktopPath -ChildPath ($ShortcutName + ".lnk")

# ---------------------------[ Detection ]---------------------------
$failure = $false

# 1) Check RDP file
Write-Log "Checking for RDP file: $TargetRdpPath" -Tag "Check"
if (Test-Path -LiteralPath $TargetRdpPath) {
    Write-Log "RDP file exists." -Tag "Success"
} else {
    Write-Log "RDP file missing." -Tag "Error"
    $failure = $true
}

# 2) Check Icon file
Write-Log "Checking for Icon file: $TargetIconPath" -Tag "Check"
if (Test-Path -LiteralPath $TargetIconPath) {
    Write-Log "Icon file exists." -Tag "Success"
} else {
    Write-Log "Icon file missing." -Tag "Error"
    $failure = $true
}

# 3) Check Desktop Shortcut
Write-Log "Checking for Shortcut: $ShortcutPath" -Tag "Check"
if (Test-Path -LiteralPath $ShortcutPath) {
    Write-Log "Shortcut exists." -Tag "Success"
} else {
    Write-Log "Shortcut missing." -Tag "Error"
    $failure = $true
}

# ---------------------------[ Exit ]---------------------------
if (-not $failure) {
    Write-Log "All components present. Detection success." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "One or more components missing. Detection failed." -Tag "Error"
    Complete-Script -ExitCode 1

}
