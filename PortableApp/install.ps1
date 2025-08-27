# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Portable App - TeamViewerQS"
$logFileName     = "install.log"

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
$targetFolderPath  = Join-Path -Path $env:LocalAppData -ChildPath $localFolderName
$targetFilePath    = Join-Path -Path $targetFolderPath -ChildPath $fileName

$startMenuRoot     = [Environment]::GetFolderPath("StartMenu")
$startMenuPrograms = Join-Path -Path $startMenuRoot -ChildPath "Programs"
$startMenuShortcut = Join-Path -Path $startMenuPrograms -ChildPath ($shortcutName + ".lnk")

$desktopPath       = [Environment]::GetFolderPath("Desktop")
$desktopShortcut   = Join-Path -Path $desktopPath -ChildPath ($shortcutName + ".lnk")

# ---------------------------[ Helper Functions ]---------------------------

function Test-Folder {
    param([string]$path)
    Write-Log "Checking folder: $path" -Tag "Check"
    try {
        if ($false -eq (Test-Path -LiteralPath $path)) {
            Write-Log "Folder not found. Creating: $path" -Tag "Info"
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Log "Folder created: $path" -Tag "Success"
        } else {
            Write-Log "Folder already exists: $path" -Tag "Success"
        }
        return $true
    } catch {
        Write-Log "Failed to ensure folder '$path'. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Get-FileSHA256 {
    param([string]$path)
    try {
        if ($true -eq (Test-Path -LiteralPath $path)) {
            $hash = Get-FileHash -Path $path -Algorithm SHA256
            return $hash.Hash.ToUpperInvariant()
        }
    } catch {
        Write-Log "Hashing failed for '$path'. Error: $($_.Exception.Message)" -Tag "Error"
    }
    return $null
}

function Copy-WithHashCheck {
    param(
        [Parameter(Mandatory=$true)][string]$source,
        [Parameter(Mandatory=$true)][string]$destination,
        [Parameter()][AllowEmptyString()][string]$expectedSHA256
    )

    Write-Log "Preparing to ensure file. Destination: $destination" -Tag "Check"

    if ($false -eq (Test-Path -LiteralPath $source)) {
        Write-Log "Source file not found: '$source'." -Tag "Error"
        return $false
    }

    # Determine expected hash
    $expected = if ([string]::IsNullOrWhiteSpace($expectedSHA256)) { Get-FileSHA256 -Path $source } else { $expectedSHA256.ToUpperInvariant() }
    if ($null -eq $expected) {
        Write-Log "Could not determine expected hash from source '$source'." -Tag "Error"
        return $false
    }

    # Verify source integrity
    $srcHash = Get-FileSHA256 -Path $source
    if ($srcHash -ne $expected) {
        Write-Log "Source hash mismatch!`n  Expected: $expected`n  Actual:   $srcHash" -Tag "Error"
        return $false
    } else {
        Write-Log "Source file hash OK." -Tag "Success"
    }

    # If destination exists and already correct, skip copy
    if ($true -eq (Test-Path -LiteralPath $destination)) {
        $dstHash = Get-FileSHA256 -Path $destination
        if ($null -ne $dstHash -and $dstHash -eq $expected) {
            Write-Log "Destination already up-to-date. Skipping copy." -Tag "Success"
            return $true
        } else {
            Write-Log "Destination differs or hash unreadable. Will overwrite." -Tag "Info"
        }
    } else {
        Write-Log "Destination not present. Will copy." -Tag "Info"
    }

    try {
        # Ensure destination folder exists
        $destDir = Split-Path -Path $destination -Parent
        if ($false -eq (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        Copy-Item -LiteralPath $source -Destination $destination -Force
        $postHash = Get-FileSHA256 -Path $destination
        if ($null -ne $postHash -and $postHash -eq $expected) {
            Write-Log "File copied/updated successfully and verified." -Tag "Success"
            return $true
        } else {
            Write-Log "Post-copy hash mismatch!`n  Expected: $expected`n  Actual:   $postHash" -Tag "Error"
            return $false
        }
    } catch {
        Write-Log "Failed to copy file. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function New-ShortcutIfMissing {
    param(
        [string]$shortcutFilePath,
        [string]$targetPath,
        [string]$description = "Portable app shortcut"
    )

    Write-Log "Ensuring shortcut: $shortcutFilePath" -Tag "Check"

    try {
        if ($false -eq (Test-Path -LiteralPath $shortcutFilePath)) {
            if ($false -eq (Test-Path -LiteralPath $targetPath)) {
                Write-Log "Cannot create shortcut. Target missing: '$targetPath'." -Tag "Error"
                return $false
            }

            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($shortcutFilePath)
            $shortcut.TargetPath       = $targetPath
            $shortcut.WorkingDirectory = (Split-Path -Path $targetPath -Parent)
            $shortcut.Description      = $description
            $shortcut.WindowStyle      = 1
            $shortcut.Save()
            Write-Log "Shortcut created." -Tag "Success"
        } else {
            Write-Log "Shortcut already exists." -Tag "Success"
        }
        return $true
    } catch {
        Write-Log "Failed to create shortcut. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

# ---------------------------[ Main ]---------------------------

# 1) Ensure folders
if ($false -eq (Test-Folder -Path $targetFolderPath))  { Complete-Script -ExitCode 1 }
if ($false -eq (Test-Folder -Path $startMenuPrograms)) { Complete-Script -ExitCode 1 }

# 2) Copy the file with hash verification
if ($false -eq (Copy-WithHashCheck -Source $fileSourcePath -Destination $targetFilePath -ExpectedSHA256 $fileExpectedSHA256)) {
    Complete-Script -ExitCode 1
}

# 3) Create Start Menu shortcut (always)
if ($false -eq (New-ShortcutIfMissing -ShortcutFilePath $startMenuShortcut -TargetPath $targetFilePath)) {
    Complete-Script -ExitCode 1
}

# 4) Create Desktop shortcut (conditional)
if ($true -eq $createDesktopShortcut) {
    if ($false -eq (New-ShortcutIfMissing -ShortcutFilePath $desktopShortcut -TargetPath $targetFilePath)) {
        Complete-Script -ExitCode 1
    }
} else {
    Write-Log "Desktop shortcut creation is disabled." -Tag "Info"
}

# 5) Validate
Write-Log "Validating final state..." -Tag "Check"
$fileExists  = Test-Path -LiteralPath $targetFilePath
$menuExists  = Test-Path -LiteralPath $startMenuShortcut
$deskExists  = if ($true -eq $createDesktopShortcut) { Test-Path -LiteralPath $desktopShortcut } else { $true }

if ($fileExists -and $menuExists -and $deskExists) {
    Write-Log "Validation OK.`n File: '$targetFilePath'`n StartMenu: '$startMenuShortcut'`n DesktopEnabled=$createDesktopShortcut" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    if ($true -ne $fileExists) { Write-Log "Missing file: $targetFilePath" -Tag "Error" }
    if ($true -ne $menuExists) { Write-Log "Missing Start Menu shortcut: $startMenuShortcut" -Tag "Error" }
    if ($true -eq $createDesktopShortcut -and $true -ne $deskExists) { Write-Log "Missing Desktop shortcut: $desktopShortcut" -Tag "Error" }
    Complete-Script -ExitCode 1
}