# ===========================[ Script Start Timestamp ]====================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]=============================

# Name of application (used for logging / context only when using packaged uninstaller)
$applicationName              = "Global Secure Access Client"

# Use the EXE/MSI bundled inside the IntuneWin package for uninstall?
# $true  = use packaged installer ONLY (no registry lookup at all)
# $false = use registry UninstallString detection logic
$usePackagedUninstaller       = $true

# Packaged uninstaller configuration (used only when $usePackagedUninstaller = $true)
# This file must be included next to the script in the IntuneWin package
$installerName                = "GlobalSecureAccessClient.exe"
$installerPath                = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# Uninstaller arguments
$uninstallerArgumentsExe      = "/uninstall /quiet /norestart"     # For non-MSI uninstallers (packaged or registry-based)
$uninstallerArgumentsMsi      = "/qn"                              # For MSI uninstall (msiexec /x ...)

# Registry locations to search for uninstall entries
# Used only when $usePackagedUninstaller = $false
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ===========================[ Logging Configuration ]=====================
$scriptName       = $applicationName
$logFileName      = "uninstall.log"

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

# ===========================[ Logging Function ]==========================
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    if (-not $log) { return }

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

# ===========================[ Exit Function ]=============================
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

# ===========================[ Script Start ]===============================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

Write-Log "Log file: '$logFile'" -Tag "Debug"

# ========================================================================
#  MODE 1: PACKAGED UNINSTALLER (NO REGISTRY USED AT ALL)
# ========================================================================
if ($usePackagedUninstaller) {

    Write-Log "Configured to use packaged installer for uninstall. Registry detection will be skipped." -Tag "Info"

    if (-not (Test-Path -Path $installerPath)) {
        Write-Log "Packaged installer not found at path: $installerPath" -Tag "Error"
        Stop-Script -ExitCode 1
    }

    Write-Log "Packaged installer found at path: $installerPath" -Tag "Success"

    $installerExtension = [System.IO.Path]::GetExtension($installerPath)
    Write-Log "Detected packaged installer extension: '$installerExtension'" -Tag "Debug"

    $filePath     = $null
    $argumentList = $null

    switch ($installerExtension.ToLowerInvariant()) {
        ".msi" {
            Write-Log "Packaged installer identified as MSI. Preparing msiexec uninstall command line." -Tag "Info"
            $filePath     = "msiexec.exe"
            $argumentList = "/x `"$installerPath`" $uninstallerArgumentsMsi"

            Write-Log "MSI uninstall file: $filePath" -Tag "Debug"
            Write-Log "MSI uninstall arguments: $argumentList" -Tag "Debug"
        }
        ".exe" {
            Write-Log "Packaged installer identified as EXE. Using EXE uninstall arguments." -Tag "Info"
            $filePath     = $installerPath
            $argumentList = $uninstallerArgumentsExe

            Write-Log "EXE uninstall file: $filePath" -Tag "Debug"
            Write-Log "EXE uninstall arguments: $argumentList" -Tag "Debug"
        }
        default {
            Write-Log "Unsupported packaged installer extension '$installerExtension'. Only .exe and .msi are supported." -Tag "Error"
            Stop-Script -ExitCode 1
        }
    }

    try {
        Write-Log "Launching packaged uninstall process: '$filePath' $argumentList" -Tag "Run"

        $process = Start-Process -FilePath $filePath `
                                 -ArgumentList $argumentList `
                                 -Wait `
                                 -PassThru `
                                 -NoNewWindow

        if ($null -eq $process) {
            Write-Log "Start-Process did not return a process object. Uninstall result unknown." -Tag "Error"
            Stop-Script -ExitCode 1
        }

        Write-Log "Packaged uninstall process ID: $($process.Id)" -Tag "Debug"
        Write-Log "Packaged uninstall exit code: $($process.ExitCode)" -Tag "Get"

        if ($process.ExitCode -eq 0) {
            Write-Log "$applicationName uninstalled successfully using packaged installer." -Tag "Success"
            Stop-Script -ExitCode 0
        }
        else {
            Write-Log "Packaged uninstall returned non-zero exit code: $($process.ExitCode)" -Tag "Error"
            Stop-Script -ExitCode $process.ExitCode
        }
    }
    catch {
        Write-Log "Packaged uninstall failed with exception: $($_.Exception.Message)" -Tag "Error"
        Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
        Stop-Script -ExitCode 1
    }
}

# ========================================================================
#  MODE 2: REGISTRY-BASED UNINSTALL (ONLY IF $usePackagedUninstaller = $false)
# ========================================================================

Write-Log "Using registry-based uninstall (UninstallString) for '$applicationName'." -Tag "Info"

$applicationFound = $false

foreach ($registryPath in $registrySearchPaths) {

    Write-Log "Searching for '$applicationName' in registry path: $registryPath" -Tag "Get"

    $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
    if ($null -eq $subkeys) {
        Write-Log "No subkeys found in $registryPath" -Tag "Debug"
        continue
    }

    foreach ($subkey in $subkeys) {

        $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) { continue }

        $displayName     = $properties.DisplayName
        $uninstallString = $properties.UninstallString

        if ($displayName) {
            Write-Log "Found installed product: '$displayName'" -Tag "Debug"
        }

        if ($displayName -eq $applicationName) {

            Write-Log "Found application '$displayName'" -Tag "Success"
            $applicationFound = $true

            if (-not $uninstallString) {
                Write-Log "UninstallString missing for '$applicationName'." -Tag "Error"
                Stop-Script -ExitCode 1
            }

            Write-Log "Original uninstall string: $uninstallString" -Tag "Debug"

            $uninstallString = $uninstallString.Trim()

            # MSI vs non-MSI handling
            if ($uninstallString -match "msiexec.exe") {
                Write-Log "MSI-based uninstaller detected. Ensuring MSI uninstall arguments are present." -Tag "Info"

                if ($uninstallString -notmatch "/qn") {
                    $uninstallString += " $uninstallerArgumentsMsi"
                    Write-Log "Appended MSI uninstall arguments: $uninstallerArgumentsMsi" -Tag "Debug"
                }
                else {
                    Write-Log "MSI uninstall string already contains '/qn'." -Tag "Debug"
                }
            }
            else {
                Write-Log "Non-MSI uninstaller detected. Appending EXE uninstall arguments: $uninstallerArgumentsExe" -Tag "Info"
                $uninstallString += " $uninstallerArgumentsExe"
            }

            Write-Log "Final registry-based uninstall string: $uninstallString" -Tag "Debug"

            try {
                Write-Log "Starting uninstall process via cmd.exe /c ..." -Tag "Run"

                $process = Start-Process -FilePath "cmd.exe" `
                                         -ArgumentList "/c `"$uninstallString`"" `
                                         -Wait `
                                         -PassThru `
                                         -NoNewWindow

                if ($null -eq $process) {
                    Write-Log "Start-Process did not return a process object. Uninstall result unknown." -Tag "Error"
                    Stop-Script -ExitCode 1
                }

                Write-Log "Uninstall process ID: $($process.Id)" -Tag "Debug"
                Write-Log "Uninstall process exit code: $($process.ExitCode)" -Tag "Get"

                if ($process.ExitCode -eq 0) {
                    Write-Log "Uninstall completed successfully for '$applicationName'." -Tag "Success"
                    Stop-Script -ExitCode 0
                }
                else {
                    Write-Log "Uninstall process returned non-zero exit code: $($process.ExitCode)" -Tag "Error"
                    Stop-Script -ExitCode $process.ExitCode
                }
            }
            catch {
                Write-Log "Uninstall failed with exception: $($_.Exception.Message)" -Tag "Error"
                Write-Log "Exception details: $($_ | Out-String)" -Tag "Debug"
                Stop-Script -ExitCode 1
            }
        }
    }
}

if (-not $applicationFound) {
    Write-Log "Application '$applicationName' not found in registry." -Tag "Error"
    Stop-Script -ExitCode 1
}