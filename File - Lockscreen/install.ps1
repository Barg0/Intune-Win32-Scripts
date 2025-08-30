# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$applicationName = "File - Lockscreen"
$logFileName = "install.log"

# ---------------------------[ Config ]---------------------------

$FileName       = "Lockscreen.jpg"
$ExpectedSHA256 = "0A06A3A8185289DF7D88A8B93F75D151005C4218ECA750644837FCCE3B588317"
$DestFolder     = Join-Path $env:ProgramData -ChildPath "IntuneFiles\Wallpaper"
$SourceFile     = Join-Path $PSScriptRoot -ChildPath $FileName
$DestFile       = Join-Path $DestFolder -ChildPath $FileName

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$applicationName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if logging is disabled

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
        "Debug"   { "DarkYellow"}
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

# ---------------------------[ Exit Function ]---------------------------

function Complete-Script {
    param([int]$ExitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Application: $applicationName" -Tag "Info"

# ---------------------------[ Helpers ]---------------------------
function Get-Hash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant() } catch { $null }
}

# ---------------------------[ Main ]---------------------------
if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Log "Packaged source missing: $SourceFile" -Tag "Error"
    Complete-Script -ExitCode 1
}

if ([string]::IsNullOrWhiteSpace($ExpectedSHA256)) {
    Write-Log "Expected SHA256 not set. Please set `$ExpectedSHA256." -Tag "Error"
    Complete-Script -ExitCode 1
}

# Verify source integrity
$srcHash = Get-Hash -Path $SourceFile
if ($null -eq $srcHash -or $srcHash -ne $ExpectedSHA256) {
    Write-Log "Source hash mismatch. Expected: $ExpectedSHA256 | Actual: $srcHash" -Tag "Error"
    Complete-Script -ExitCode 1
}
Write-Log "Source hash OK." -Tag "Success"

# Ensure destination folder
if (-not (Test-Path -LiteralPath $DestFolder)) {
    try {
        New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
        Write-Log "Created destination folder: $DestFolder" -Tag "Success"
    } catch {
        Write-Log "Failed to create $DestFolder : $($_.Exception.Message)" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

# If destination already matches expected hash, skip copy
if (Test-Path -LiteralPath $DestFile) {
    $dstHash = Get-Hash -Path $DestFile
    if ($null -ne $dstHash -and $dstHash -eq $ExpectedSHA256) {
        Write-Log "Destination already up-to-date. No copy needed." -Tag "Success"
        Complete-Script -ExitCode 0
    }
}

# Copy and verify
try {
    Copy-Item -LiteralPath $SourceFile -Destination $DestFile -Force
    Write-Log "Copied file to $DestFile" -Tag "Info"
} catch {
    Write-Log "Copy failed: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}

$postHash = Get-Hash -Path $DestFile
if ($null -eq $postHash -or $postHash -ne $ExpectedSHA256) {
    Write-Log "Post-copy hash mismatch. Expected: $ExpectedSHA256 | Actual: $postHash" -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "File deployed and verified at: $DestFile" -Tag "Success"
Complete-Script -ExitCode 0