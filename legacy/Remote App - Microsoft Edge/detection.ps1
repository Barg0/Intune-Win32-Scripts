# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "detection.log"

# ---------------------------[ Configurable Variables ]---------------------------
$localFolderName       = "RemoteDesktopApps"
$fileName              = "MicrosoftEdge.rdp"
$iconFileName          = "MicrosoftEdge.ico"

# unified shortcut display name (no .lnk)
$shortcutName          = "Microsoft Edge (RDP)"

# toggle for desktop shortcut
$createDesktopShortcut = $true

# optional expected file hash (if empty, hash check is skipped here)
$fileExpectedSHA256    = "0FB0A957A8B997D0F7725243A56150975D456EDD5DB2721D39066662F0D71425"

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

function Get-FileSHA256 {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            $hash = Get-FileHash -Path $Path -Algorithm SHA256
            return $hash.Hash.ToUpperInvariant()
        }
    } catch {
        Write-Log "Hashing failed for '$Path'. Error: $($_.Exception.Message)" -Tag "Error"
    }
    return $null
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

# ---------------------------[ Detection ]---------------------------
$failure = $false

# 1) Check main file
Write-Log "Checking for file: $targetFilePath" -Tag "Check"
if (Test-Path -LiteralPath $targetFilePath) {
    Write-Log "File exists." -Tag "Success"

    if (-not [string]::IsNullOrWhiteSpace($fileExpectedSHA256)) {
        $installedHash = Get-FileSHA256 -Path $targetFilePath
        if ($null -eq $installedHash) {
            Write-Log "Could not compute installed file hash." -Tag "Error"
            $failure = $true
        } elseif ($installedHash -ne $fileExpectedSHA256.ToUpperInvariant()) {
            Write-Log "Installed file hash mismatch. Expected: $($fileExpectedSHA256.ToUpperInvariant()) ; Actual: $installedHash" -Tag "Error"
            $failure = $true
        } else {
            Write-Log "Installed file hash OK." -Tag "Success"
        }
    } else {
        Write-Log "No expected hash provided; skipping hash validation." -Tag "Info"
    }
} else {
    Write-Log "File missing." -Tag "Error"
    $failure = $true
}

# 2) Check Icon file
Write-Log "Checking for Icon file: $targetIconPath" -Tag "Check"
if (Test-Path -LiteralPath $targetIconPath) {
    Write-Log "Icon file exists." -Tag "Success"
} else {
    Write-Log "Icon file missing." -Tag "Error"
    $failure = $true
}

# 3) Check Desktop Shortcut (conditional)
if ($createDesktopShortcut) {
    Write-Log "Checking for Desktop shortcut: $desktopShortcutPath" -Tag "Check"
    if (Test-Path -LiteralPath $desktopShortcutPath) {
        Write-Log "Desktop shortcut exists." -Tag "Success"
    } else {
        Write-Log "Desktop shortcut missing (toggle enabled)." -Tag "Error"
        $failure = $true
    }
} else {
    Write-Log "Desktop shortcut disabled by configuration; skipping check." -Tag "Info"
}

# 4) Check Start Menu Shortcut (always)
Write-Log "Checking for Start Menu shortcut: $startMenuShortcutPath" -Tag "Check"
if (Test-Path -LiteralPath $startMenuShortcutPath) {
    Write-Log "Start Menu shortcut exists." -Tag "Success"
} else {
    Write-Log "Start Menu shortcut missing." -Tag "Error"
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
