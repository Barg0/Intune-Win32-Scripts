# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "install.log"

# ---------------------------[ Configurable Variables ]---------------------------
$localFolderName = "RemoteDesktopApps"
$fileName     = "MicrosoftEdge.rdp"
$iconFileName = "MicrosoftEdge.ico"

# Unified shortcut display name (no .lnk)
$shortcutName    = "Microsoft Edge (RDP)"

# Toggle: create Desktop Shortcut?
$createDesktopShortcut = $true

# Expected SHA256 hash of the main file
# Leave empty to auto-derive from packaged source
$fileExpectedSHA256 = "0FB0A957A8B997D0F7725243A56150975D456EDD5DB2721D39066662F0D71425"

# Where the packaged files are relative to this script:
$fileSourcePath  = Join-Path -Path $PSScriptRoot -ChildPath $fileName
$iconSourcePath  = Join-Path -Path $PSScriptRoot -ChildPath $iconFileName

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
$targetFolderPath  = Join-Path -Path $env:LocalAppData -ChildPath $localFolderName
$targetFilePath    = Join-Path -Path $targetFolderPath -ChildPath $fileName
$targetIconPath    = Join-Path -Path $targetFolderPath -ChildPath $iconFileName

$desktopPath       = [Environment]::GetFolderPath("Desktop")
$desktopShortcut   = Join-Path -Path $desktopPath -ChildPath ($shortcutName + ".lnk")

$startMenuRoot     = [Environment]::GetFolderPath("StartMenu")
$startMenuPrograms = Join-Path -Path $startMenuRoot -ChildPath "Programs"
$startMenuShortcut = Join-Path -Path $startMenuPrograms -ChildPath ($shortcutName + ".lnk")

# ---------------------------[ Helper Functions ]---------------------------

function Test-Folder {
    param([string]$Path)
    Write-Log "Checking folder: $Path" -Tag "Check"
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Log "Folder not found. Creating: $Path" -Tag "Info"
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Folder created: $Path" -Tag "Success"
        } else {
            Write-Log "Folder already exists: $Path" -Tag "Success"
        }
        return $true
    } catch {
        Write-Log "Failed to ensure folder '$Path'. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Copy-IfMissing {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ItemLabel
    )
    Write-Log "Checking $ItemLabel at: $Destination" -Tag "Check"

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Log "Source $ItemLabel not found at '$Source'. Package content may be missing." -Tag "Error"
        return $false
    }

    try {
        if (-not (Test-Path -LiteralPath $Destination)) {
            Write-Log "$ItemLabel not present. Copying '$Source' -> '$Destination'" -Tag "Info"
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            Write-Log "$ItemLabel copied to target." -Tag "Success"
        } else {
            Write-Log "$ItemLabel already present at target." -Tag "Success"
        }
        return $true
    } catch {
        Write-Log "Failed to copy $ItemLabel. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Copy-WithHashCheck {
    <#
        Ensures the main file is present with SHA256 verification:
        - If $fileExpectedSHA256 provided: verify SOURCE matches it (tamper check).
        - If DEST exists and hash equals expected -> skip copy.
        - Else copy/overwrite and verify.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter()][AllowEmptyString()][string]$ExpectedSHA256
    )

    Write-Log "Preparing to ensure file with hash verification. Destination: $Destination" -Tag "Check"

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Log "Source file not found: '$Source'." -Tag "Error"
        return $false
    }

    # Determine expected hash
    $expected = if ([string]::IsNullOrWhiteSpace($ExpectedSHA256)) { Get-FileSHA256 -Path $Source } else { $ExpectedSHA256.ToUpperInvariant() }
    if ($null -eq $expected) {
        Write-Log "Could not determine expected hash from source '$Source'." -Tag "Error"
        return $false
    }

    # Verify source integrity
    $srcHash = Get-FileSHA256 -Path $Source
    if ($srcHash -ne $expected) {
        Write-Log "Source hash mismatch! Expected: $expected ; Actual: $srcHash" -Tag "Error"
        return $false
    } else {
        Write-Log "Source file hash OK." -Tag "Success"
    }

    # If destination exists and already correct, skip copy
    if (Test-Path -LiteralPath $Destination) {
        $dstHash = Get-FileSHA256 -Path $Destination
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
        $destDir = Split-Path -Path $Destination -Parent
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        $postHash = Get-FileSHA256 -Path $Destination
        if ($null -ne $postHash -and $postHash -eq $expected) {
            Write-Log "File copied/updated successfully and verified." -Tag "Success"
            return $true
        } else {
            Write-Log "Post-copy hash mismatch! Expected: $expected ; Actual: $postHash" -Tag "Error"
            return $false
        }
    } catch {
        Write-Log "Failed to copy file. Error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function New-ShortcutIfMissing {
    param(
        [string]$ShortcutFilePath,
        [string]$TargetPath,
        [string]$IconPath,
        [string]$Description = "Remote Desktop connection"
    )

    Write-Log "Checking shortcut: $ShortcutFilePath" -Tag "Check"

    try {
        if (-not (Test-Path -LiteralPath $ShortcutFilePath)) {
            if (-not (Test-Path -LiteralPath $TargetPath)) {
                Write-Log "Cannot create shortcut. Target '$TargetPath' is missing." -Tag "Error"
                return $false
            }
            if (-not (Test-Path -LiteralPath $IconPath)) {
                Write-Log "Cannot create shortcut. Icon file '$IconPath' is missing." -Tag "Error"
                return $false
            }

            Write-Log "Creating shortcut at '$ShortcutFilePath'." -Tag "Info"
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($ShortcutFilePath)
            $shortcut.TargetPath      = $TargetPath
            $shortcut.WorkingDirectory= Split-Path -Path $TargetPath -Parent
            $shortcut.Description     = $Description
            $shortcut.IconLocation    = $IconPath
            $shortcut.WindowStyle     = 1
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

# 1) Ensure target folder in %LocalAppData%
if (-not (Test-Folder -Path $targetFolderPath)) { Complete-Script -ExitCode 1 }

# 2) Copy main file with hash verification & copy icon if missing
if (-not (Copy-WithHashCheck -Source $fileSourcePath  -Destination $targetFilePath  -ExpectedSHA256 $fileExpectedSHA256))  { Complete-Script -ExitCode 1 }
if (-not (Copy-IfMissing     -Source $iconSourcePath  -Destination $targetIconPath  -ItemLabel "Icon file"))               { Complete-Script -ExitCode 1 }

# 3) Ensure Start Menu\Programs exists
if (-not (Test-Folder -Path $startMenuPrograms)) { Complete-Script -ExitCode 1 }

# 4) Create/ensure Start Menu shortcut (always) & Desktop shortcut (conditional)
if (-not (New-ShortcutIfMissing -ShortcutFilePath $startMenuShortcut -TargetPath $targetFilePath -IconPath $targetIconPath))  { Complete-Script -ExitCode 1 }

if ($createDesktopShortcut) {
    if (-not (New-ShortcutIfMissing -ShortcutFilePath $desktopShortcut   -TargetPath $targetFilePath -IconPath $targetIconPath))  { Complete-Script -ExitCode 1 }
} else {
    Write-Log "Desktop shortcut creation disabled by configuration." -Tag "Info"
}

# 5) Final validation
Write-Log "Validating final state (file, icon, shortcuts)..." -Tag "Check"

$fileExists  = Test-Path -LiteralPath $targetFilePath
$icoExists   = Test-Path -LiteralPath $targetIconPath
$menuExists  = Test-Path -LiteralPath $startMenuShortcut
$deskExists  = if ($createDesktopShortcut) { Test-Path -LiteralPath $desktopShortcut } else { $true }

if ($fileExists -and $icoExists -and $menuExists -and $deskExists) {
    Write-Log "Validation OK.`n File: '$targetFilePath'`n Icon: '$targetIconPath'`n StartMenu: '$startMenuShortcut'`n DesktopEnabled=$createDesktopShortcut" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    if (-not $fileExists)  { Write-Log "Missing file: $targetFilePath" -Tag "Error" }
    if (-not $icoExists)   { Write-Log "Missing icon: $targetIconPath" -Tag "Error" }
    if (-not $menuExists)  { Write-Log "Missing start menu shortcut: $startMenuShortcut" -Tag "Error" }
    if ($createDesktopShortcut -and (-not $deskExists)) { Write-Log "Missing desktop shortcut: $desktopShortcut" -Tag "Error" }
    Complete-Script -ExitCode 1
}