# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "uninstall.log"

# ---------------------------[ Configurable Variables ]---------------------------
$localFolderName       = "RemoteDesktopApps"
$fileName              = "MicrosoftEdge.rdp"
$iconFileName          = "MicrosoftEdge.ico"

# unified shortcut display name (no .lnk)
$shortcutName          = "Microsoft Edge (RDP)"

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

# ---------------------------[ Folders ]---------------------------
$targetFolderPath      = Join-Path -Path $env:LocalAppData -ChildPath $localFolderName
$targetFilePath        = Join-Path -Path $targetFolderPath -ChildPath $fileName
$targetIconPath        = Join-Path -Path $targetFolderPath -ChildPath $iconFileName

$desktopPath           = [Environment]::GetFolderPath("Desktop")
$desktopShortcutPath   = Join-Path -Path $desktopPath -ChildPath ($shortcutName + ".lnk")

$startMenuRoot         = [Environment]::GetFolderPath("StartMenu")
$startMenuPrograms     = Join-Path -Path $startMenuRoot -ChildPath "Programs"
$startMenuShortcutPath = Join-Path -Path $startMenuPrograms -ChildPath ($shortcutName + ".lnk")

# ---------------------------[ Removal Steps ]---------------------------

# 1) Remove Desktop Shortcut
Write-Log "Checking for desktop shortcut: $desktopShortcutPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $desktopShortcutPath) {
        Write-Log "Shortcut found. Deleting: $desktopShortcutPath" -Tag "Info"
        Remove-Item -LiteralPath $desktopShortcutPath -Force
        Write-Log "Desktop shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Desktop shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove desktop shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 2) Remove Start Menu Shortcut
Write-Log "Checking for Start Menu shortcut: $startMenuShortcutPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $startMenuShortcutPath) {
        Write-Log "Shortcut found. Deleting: $startMenuShortcutPath" -Tag "Info"
        Remove-Item -LiteralPath $startMenuShortcutPath -Force
        Write-Log "Start Menu shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Start Menu shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove Start Menu shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 3) Remove main file
Write-Log "Checking for file: $targetFilePath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $targetFilePath) {
        Write-Log "File found. Deleting: $targetFilePath" -Tag "Info"
        Remove-Item -LiteralPath $targetFilePath -Force
        Write-Log "File deleted." -Tag "Success"
    } else {
        Write-Log "File not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove file. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 4) Remove Icon file
Write-Log "Checking for icon file: $targetIconPath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $targetIconPath) {
        Write-Log "Icon file found. Deleting: $targetIconPath" -Tag "Info"
        Remove-Item -LiteralPath $targetIconPath -Force
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
