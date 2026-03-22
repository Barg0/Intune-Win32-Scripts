# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Portable App Deployer"
$logFileName     = "uninstall.log"

# ---------------------------[ Configurable Variables ]---------------------------
$localFolderName = "PortableApps"
$fileName        = "TeamViewerQS.exe"

# Packaged source file (unused here, kept for alignment)
$fileSourcePath  = Join-Path -Path $PSScriptRoot -ChildPath $fileName

# Shortcut display names (no .lnk) (for Startmenu and Desktop)
$shortcutName    = "TeamViewerQS"

# Toggle: create Desktop Shortcut? (used to decide whether its absence matters during detection;
# here we'll try to remove it either way if found)
$createDesktopShortcut = $true

# Expected SHA256 hash of file (not used here)
$fileExpectedSHA256 = ""

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$($env:USERNAME)\$applicationName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and (-not (Test-Path -LiteralPath $logFileDirectory))) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$message, [string]$tag = "Info")

    if ($false -eq $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $tag.Trim()

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

    $logMessage = "$timestamp [  $rawTag ] $message"
    if ($enableLogFile) { "$logMessage" | Out-File -FilePath $logFile -Append -Encoding UTF8 }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

function Complete-Script {
    param([int]$exitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $exitCode
}

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ Derived Paths ]---------------------------
$targetFolderPath   = Join-Path -Path $env:LocalAppData -ChildPath $localFolderName
$targetFilePath     = Join-Path -Path $targetFolderPath -ChildPath $fileName

$startMenuRoot      = [Environment]::GetFolderPath("StartMenu")
$startMenuPrograms  = Join-Path -Path $startMenuRoot -ChildPath "Programs"
$startMenuShortcut  = Join-Path -Path $startMenuPrograms -ChildPath ($shortcutName + ".lnk")

$desktopPath        = [Environment]::GetFolderPath("Desktop")
$desktopShortcut    = Join-Path -Path $desktopPath -ChildPath ($shortcutName + ".lnk")

# ---------------------------[ Removal Steps ]---------------------------

# 1) Remove Desktop Shortcut (best-effort)
Write-Log "Checking for Desktop shortcut: $desktopShortcut" -Tag "Check"
try {
    if (Test-Path -LiteralPath $desktopShortcut) {
        Write-Log "Deleting Desktop shortcut: $desktopShortcut" -Tag "Info"
        Remove-Item -LiteralPath $desktopShortcut -Force
        Write-Log "Desktop shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Desktop shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove Desktop shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 2) Remove Start Menu Shortcut
Write-Log "Checking for Start Menu shortcut: $startMenuShortcut" -Tag "Check"
try {
    if (Test-Path -LiteralPath $startMenuShortcut) {
        Write-Log "Deleting Start Menu shortcut: $startMenuShortcut" -Tag "Info"
        Remove-Item -LiteralPath $startMenuShortcut -Force
        Write-Log "Start Menu shortcut deleted." -Tag "Success"
    } else {
        Write-Log "Start Menu shortcut not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove Start Menu shortcut. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 3) Remove file
Write-Log "Checking for file: $targetFilePath" -Tag "Check"
try {
    if (Test-Path -LiteralPath $targetFilePath) {
        Write-Log "Deleting file: $targetFilePath" -Tag "Info"
        Remove-Item -LiteralPath $targetFilePath -Force
        Write-Log "File deleted." -Tag "Success"
    } else {
        Write-Log "File not found. Nothing to remove." -Tag "Info"
    }
} catch {
    Write-Log "Failed to remove file. Error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

# 4) Optional: remove folder if empty
try {
    if (Test-Path -LiteralPath $targetFolderPath) {
        $remaining = Get-ChildItem -LiteralPath $targetFolderPath -Force | Measure-Object
        if ($remaining.Count -eq 0) {
            Write-Log "Target folder is empty. Removing: $targetFolderPath" -Tag "Info"
            Remove-Item -LiteralPath $targetFolderPath -Force
            Write-Log "Target folder removed." -Tag "Success"
        } else {
            Write-Log "Target folder not empty; leaving in place." -Tag "Info"
        }
    }
} catch {
    Write-Log "Failed folder cleanup. Error: $($_.Exception.Message)" -Tag "Error"
    # Not fatal for uninstall completion
}

Write-Log "Uninstall cleanup complete." -Tag "Success"
Complete-Script -ExitCode 0
