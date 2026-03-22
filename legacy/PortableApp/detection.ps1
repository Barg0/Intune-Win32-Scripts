# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Portable App Deployer"
$logFileName     = "detection.log"

# ---------------------------[ Configurable Variables ]---------------------------
$localFolderName = "PortableApps"
$fileName        = "TeamViewerQS.exe"

# Packaged source file
$fileSourcePath  = Join-Path -Path $PSScriptRoot -ChildPath $fileName

# Shortcut display names (no .lnk) (for Startmenu and Desktop)
$shortcutName    = "TeamViewerQS"

# Toggle: create Desktop Shortcut?
$createDesktopShortcut = $true

# Expected SHA256 hash of file
$fileExpectedSHA256 = "DFCDA9F8A46EFC5E6D14EE9F47BC3204BCFC515FCC2AD6DF05BFCCA80BD65F4A"

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

# ---------------------------[ Detection ]---------------------------
$failure = $false

# 1) Check file
Write-Log "Checking for file: $targetFilePath" -Tag "Check"
if (Test-Path -LiteralPath $targetFilePath) {
    Write-Log "File exists." -Tag "Success"
} else {
    Write-Log "File missing." -Tag "Error"
    $failure = $true
}

# 2) Check Start Menu Shortcut (always expected)
Write-Log "Checking for Start Menu shortcut: $startMenuShortcut" -Tag "Check"
if (Test-Path -LiteralPath $startMenuShortcut) {
    Write-Log "Start Menu shortcut exists." -Tag "Success"
} else {
    Write-Log "Start Menu shortcut missing." -Tag "Error"
    $failure = $true
}

# 3) Check Desktop Shortcut (only when enabled)
if ($true -eq $createDesktopShortcut) {
    Write-Log "Checking for Desktop shortcut: $desktopShortcut" -Tag "Check"
    if (Test-Path -LiteralPath $desktopShortcut) {
        Write-Log "Desktop shortcut exists." -Tag "Success"
    } else {
        Write-Log "Desktop shortcut missing (toggle enabled)." -Tag "Error"
        $failure = $true
    }
} else {
    Write-Log "Desktop shortcut disabled by configuration; skipping check." -Tag "Info"
}

# ---------------------------[ Exit ]---------------------------
if ($false -eq $failure) {
    Write-Log "All components present. Detection success." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "One or more components missing. Detection failed." -Tag "Error"
    Complete-Script -ExitCode 1
}
