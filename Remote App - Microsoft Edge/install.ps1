# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$applicationName = "Remote App - Microsoft Edge"
$logFileName = "install.log"

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

# ---------------------------[ Variables You May Change ]---------------------------
$LocalFolderName = "RemoteDesktopApps"

$RdpFileName     = "MicrosoftEdge.rdp"
$IconFileName    = "MicrosoftEdge.ico"

# Where the packaged files are relative to this script:
$RdpSourcePath   = Join-Path -Path $PSScriptRoot -ChildPath $RdpFileName
$IconSourcePath  = Join-Path -Path $PSScriptRoot -ChildPath $IconFileName

# Shortcut display names (no .lnk in the name)
$DesktopShortcutName   = "Microsoft Edge (RDP)"
$StartMenuShortcutName = "Microsoft Edge (RDP)"

# ---------------------------[ Derived Paths ]---------------------------
$TargetFolderPath   = Join-Path -Path $env:LocalAppData -ChildPath $LocalFolderName
$TargetRdpPath      = Join-Path -Path $TargetFolderPath -ChildPath $RdpFileName
$TargetIconPath     = Join-Path -Path $TargetFolderPath -ChildPath $IconFileName

$DesktopPath        = [Environment]::GetFolderPath("Desktop")
$DesktopShortcut    = Join-Path -Path $DesktopPath -ChildPath ($DesktopShortcutName + ".lnk")

$StartMenuRoot      = [Environment]::GetFolderPath("StartMenu")         # e.g. C:\Users\<u>\AppData\Roaming\Microsoft\Windows\Start Menu
$StartMenuPrograms  = Join-Path -Path $StartMenuRoot -ChildPath "Programs"
$StartMenuShortcut  = Join-Path -Path $StartMenuPrograms -ChildPath ($StartMenuShortcutName + ".lnk")

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
            $shortcut.IconLocation    = $IconPath      # .ico file path (no index)
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
if (-not (Test-Folder -Path $TargetFolderPath)) { Complete-Script -ExitCode 1 }

# 2) Copy RDP & Icon if missing
if (-not (Copy-IfMissing -Source $RdpSourcePath  -Destination $TargetRdpPath  -ItemLabel "RDP file"))  { Complete-Script -ExitCode 1 }
if (-not (Copy-IfMissing -Source $IconSourcePath -Destination $TargetIconPath -ItemLabel "Icon file")) { Complete-Script -ExitCode 1 }

# 3) Ensure Start Menu\Programs exists (it should, but be safe)
if (-not (Test-Folder -Path $StartMenuPrograms)) { Complete-Script -ExitCode 1 }

# 4) Create/ensure Desktop & Start Menu shortcuts (use the same .ico)
if (-not (New-ShortcutIfMissing -ShortcutFilePath $DesktopShortcut   -TargetPath $TargetRdpPath -IconPath $TargetIconPath))  { Complete-Script -ExitCode 1 }
if (-not (New-ShortcutIfMissing -ShortcutFilePath $StartMenuShortcut -TargetPath $TargetRdpPath -IconPath $TargetIconPath))  { Complete-Script -ExitCode 1 }

# 5) Final validation: RDP + Icon + both Shortcuts must exist
Write-Log "Validating final state (RDP, Icon, Desktop & Start Menu shortcuts)..." -Tag "Check"

$rdpExists   = Test-Path -LiteralPath $TargetRdpPath
$icoExists   = Test-Path -LiteralPath $TargetIconPath
$deskExists  = Test-Path -LiteralPath $DesktopShortcut
$menuExists  = Test-Path -LiteralPath $StartMenuShortcut

if (($true -eq $rdpExists) -and ($true -eq $icoExists) -and ($true -eq $deskExists) -and ($true -eq $menuExists)) {
    Write-Log "Validation OK.`n RDP: '$TargetRdpPath'`n Icon: '$TargetIconPath'`n Desktop: '$DesktopShortcut'`n StartMenu: '$StartMenuShortcut'" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    if ($true -ne $rdpExists)  { Write-Log "Missing file: $TargetRdpPath"       -Tag "Error" }
    if ($true -ne $icoExists)  { Write-Log "Missing icon: $TargetIconPath"      -Tag "Error" }
    if ($true -ne $deskExists) { Write-Log "Missing desktop shortcut: $DesktopShortcut" -Tag "Error" }
    if ($true -ne $menuExists) { Write-Log "Missing start menu shortcut: $StartMenuShortcut" -Tag "Error" }
    Complete-Script -ExitCode 1
}