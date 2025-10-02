# ====================[ Script Start Timestamp ]===================

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ===========================[ CONFIG ]===========================
# ---- Web link details (edit these for your app) ----
$linkName         = "Google"                # Shortcut display name (no extension)
$targetUrl        = "https://google.com"    # Target URL
$iconFileName     = "Google.ico"            # Icon file included in the package

# ---- Folder/paths (usually OK as-is) ----
$appFolderName    = "WebLinkIcons"                             # Folder created in %LOCALAPPDATA%

# ---- Derived paths (do not change unless necessary) ----
$shortcutFileName = "$linkName.url"                               # Unified shortcut filename
$localAppDataPath = $env:LOCALAPPDATA
$destinationFolder = Join-Path -Path $localAppDataPath -ChildPath $appFolderName

$desktopPath       = [Environment]::GetFolderPath('Desktop')
$startMenuPath     = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs"

$desktopShortcutPath   = Join-Path -Path $desktopPath   -ChildPath $shortcutFileName
$startMenuShortcutPath = Join-Path -Path $startMenuPath -ChildPath $shortcutFileName

# =========================[ Script name ]=========================

# Script name used for folder/log naming
$scriptName = "WebLink - $linkName"
$logFileName = "install.log"

# =========================[ Logging Setup ]=======================

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output
$logDebug = $false               # Set to $true to allow debug logs

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$($env:USERNAME)\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    [CmdletBinding()]
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if all logging disabled

    # Handle debug suppression
    if ($Tag -eq "Debug" -and -not $logDebug) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "  # Fallback if an unrecognized tag is used
    }

    # Set tag colors
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

    # Write to file if enabled
    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    # Write to console with color formatting
    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

# =========================[ Exit Function ]=======================

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
# Complete-Script -ExitCode 0

# =========================[ Helper Functions ]====================

function New-FolderIfMissing {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        Write-Log "Creating folder: $Path" -Tag "Info"
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Folder created: $Path" -Tag "Success"
        } catch {
            Write-Log "Failed to create folder '$Path'. $_" -Tag "Error"
            Complete-Script -ExitCode 1
        }
    } else {
        Write-Log "Folder already exists: $Path" -Tag "Info"
    }
}

function Copy-IconFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationFolder
    )

    try {
        New-FolderIfMissing -Path $DestinationFolder
        $iconDestinationPath = Join-Path -Path $DestinationFolder -ChildPath (Split-Path -Leaf $SourcePath)
        Copy-Item -Path $SourcePath -Destination $iconDestinationPath -Force
        Write-Log "Icon copied to: $iconDestinationPath" -Tag "Success"
        return $iconDestinationPath
    } catch {
        Write-Log "Failed to copy icon from '$SourcePath' to '$DestinationFolder'. $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

function New-WebLinkFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShortcutPath,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$IconPath
    )

    $content = @"
[InternetShortcut]
URL=$Url
IconFile=$IconPath
IconIndex=0
IDList=
HotKey=0
"@

    try {
        # .url files prefer ANSI/ASCII; use ASCII for widest compatibility
        Set-Content -Path $ShortcutPath -Value $content -Encoding ASCII -Force
        Write-Log "Web link created: $ShortcutPath" -Tag "Success"
    } catch {
        Write-Log "Failed to create web link '$ShortcutPath'. $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

function Test-ShortcutExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ShortcutPath)

    if (Test-Path -Path $ShortcutPath) {
        Write-Log "Verified shortcut exists: $ShortcutPath" -Tag "Success"
        return $true
    } else {
        Write-Log "Shortcut not found: $ShortcutPath" -Tag "Error"
        return $false
    }
}

# ===========================[ Script Start ]======================

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $scriptName" -Tag "Info"

# 1) Ensure destination folder exists
Write-Log "Ensuring destination folder exists: $destinationFolder" -Tag "Debug"
New-FolderIfMissing -Path $destinationFolder

# 2) Copy icon from package folder ($PSScriptRoot) to destination
$iconSourcePath = Join-Path -Path $PSScriptRoot -ChildPath $iconFileName
if (-not (Test-Path -Path $iconSourcePath)) {
    Write-Log "Icon file not found in package: $iconSourcePath" -Tag "Error"
    Complete-Script -ExitCode 1
}
$iconPath = Copy-IconFile -SourcePath $iconSourcePath -DestinationFolder $destinationFolder

# 3) Create Desktop and Start Menu web link shortcuts
Write-Log "Creating Desktop shortcut: $desktopShortcutPath" -Tag "Debug"
New-WebLinkFile -ShortcutPath $desktopShortcutPath -Url $targetUrl -IconPath $iconPath

Write-Log "Creating Start Menu shortcut: $startMenuShortcutPath" -Tag "Debug"
New-WebLinkFile -ShortcutPath $startMenuShortcutPath -Url $targetUrl -IconPath $iconPath

# 4) Verify both shortcuts exist
$desktopOk   = Test-ShortcutExists -ShortcutPath $desktopShortcutPath
$startMenuOk = Test-ShortcutExists -ShortcutPath $startMenuShortcutPath

if ($desktopOk -and $startMenuOk) {
    Write-Log "All shortcuts created and verified successfully." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "One or more shortcuts failed verification." -Tag "Error"
    Complete-Script -ExitCode 1
}
