# ===========================[ Script Start Timestamp ]===========================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]===================================

# Script / application metadata
$applicationName  = "Global Secure Access Client"

# Installer configuration
# NOTE: This can be either .exe or .msi – behaviour changes based on extension
$installerName        = "GlobalSecureAccessClient.exe"
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# EXE installer arguments
$installerArgumentsExe = '/quiet'

# MSI installer arguments (fallback when $installerName ends with .msi)
# This will be passed to msiexec.exe
$installerArgumentsMsi = "/qn"

# ===========================[ Logging Configuration ]=====================
$scriptName       = $applicationName
$logFileName      = "install.log"

# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $false to hide DEBUG logs
$logGet        = $true    # Enable/disable all [Get] logs
$logRun        = $true    # Enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

# Ensure log directory exists
if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ===========================[ Logging Function ]================================
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches
    if (($tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($tag -eq "Get")   -and (-not $logGet))   { return }
    if (($tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    }
    else {
        # If an unknown tag is used, treat it as Error to keep things strict
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Get"     { "Blue" }
        "Run"     { "Magenta" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow" }
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $message"

    if ($enableLogFile) {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ===========================[ Exit Function ]===================================
function Stop-Script {
    [CmdletBinding()]
    param(
        [int]$exitCode
    )

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}

# ===========================[ Script Start ]====================================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

Write-Log "Script configuration - InstallerName: '$installerName'" -Tag "Debug"
Write-Log "Script configuration - InstallerPath: '$installerPath'" -Tag "Debug"
Write-Log "Script configuration - LogFile: '$logFile'" -Tag "Debug"

# ===========================[ Installer Detection ]=============================
Write-Log "Validating installer path..." -Tag "Get"

if (-not (Test-Path -Path $installerPath)) {
    Write-Log "Installer not found at path: $installerPath" -Tag "Error"
    Stop-Script -ExitCode 1
}

Write-Log "Installer found at path: $installerPath" -Tag "Success"

# Determine installer type based on file extension
$installerExtension = [System.IO.Path]::GetExtension($installerPath)
Write-Log "Detected installer extension: '$installerExtension'" -Tag "Debug"

# Prepare execution details based on installer type
$filePath      = $null
$argumentList  = $null

switch ($installerExtension.ToLowerInvariant()) {
    ".msi" {
        Write-Log "Installer identified as MSI. Preparing msiexec command line." -Tag "Info"
        $filePath     = "msiexec.exe"
        $argumentList = "/i `"$installerPath`" $installerArgumentsMsi"

        Write-Log "MSI execution file: $filePath" -Tag "Debug"
        Write-Log "MSI execution arguments: $argumentList" -Tag "Debug"
    }
    ".exe" {
        Write-Log "Installer identified as EXE. Using configured EXE arguments." -Tag "Info"
        $filePath     = $installerPath
        $argumentList = $installerArgumentsExe

        Write-Log "EXE execution file: $filePath" -Tag "Debug"
        Write-Log "EXE execution arguments: $argumentList" -Tag "Debug"
    }
    default {
        Write-Log "Unsupported installer extension '$installerExtension'. Only .exe and .msi are supported." -Tag "Error"
        Stop-Script -ExitCode 1
    }
}

# ===========================[ Install ]=========================================
Write-Log "Starting installation for '$applicationName'." -Tag "Run"

try {
    Write-Log "Launching process: '$filePath' with arguments: $argumentList" -Tag "Debug"

    $process = Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait -PassThru -NoNewWindow

    if ($null -eq $process) {
        Write-Log "Start-Process did not return a process object. Installation result is unknown." -Tag "Error"
        Stop-Script -ExitCode 1
    }

    Write-Log "Installer process ID: $($process.Id)" -Tag "Debug"
    Write-Log "Installer exited with code: $($process.ExitCode)" -Tag "Info"

    if ($process.ExitCode -eq 0) {
        Write-Log "$applicationName installed successfully." -Tag "Success"
        Stop-Script -ExitCode 0
    }
    else {
        Write-Log "Installer returned a non-zero exit code: $($process.ExitCode)" -Tag "Error"
        Stop-Script -ExitCode 1
    }
}
catch {
    Write-Log "Exception during installation: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
    Stop-Script -ExitCode 1
}
