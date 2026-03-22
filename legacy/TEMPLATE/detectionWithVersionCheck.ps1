# ===========================[ Script Start Timestamp ]===================
$scriptStartTime = Get-Date

# ===========================[ Configuration ]============================

# Application metadata
$applicationName    = "__REGISTRY_DISPLAY_NAME__"
$applicationVersion = "__REGISTRY_DISPLAY_VERSION__"

# Registry paths to search for the installed application
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Wildcard support: If $applicationName contains *, use wildcard matching in registry searches
# The clean name (without *) is used for log paths and folder names
$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) {
    # Remove wildcard characters for use in file paths
    $applicationName -replace '[\*\?\[\]]', ''
} else {
    $applicationName
}

# ===========================[ Logging Configuration ]====================
$scriptName       = $applicationNameClean
$logFileName      = "detection.log"

# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $false to hide DEBUG logs
$logGet        = $true    # Enable/disable all [Get] logs
$logRun        = $true    # Enable/disable all [Run] logs
$enableLogFile = $true

# Ensure log directory exists
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ===========================[ Logging Function ]=========================
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
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            # Logging must never block script execution - silently fail if log file is locked or inaccessible
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ===========================[ Exit Function ]============================
function Stop-Script {
    [CmdletBinding()]
    param(
        [int]$exitCode
    )

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "========== Script Completed ==========" -Tag "End"

    exit $exitCode
}

# ===========================[ Script Start ]=============================
Write-Log "========== Detection Script ==========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $applicationName" -Tag "Info"

Write-Log "Target application: '$applicationName' Version: '$applicationVersion'" -Tag "Debug"
Write-Log "Log file: '$logFile'" -Tag "Debug"

# ===========================[ Detection Logic ]==========================

$applicationFound = $false

if ($useWildcardMatching) {
    Write-Log "Checking registry for application '$applicationName' Version '$applicationVersion' (wildcard matching enabled)." -Tag "Get"
} else {
    Write-Log "Checking registry for application '$applicationName' Version '$applicationVersion'." -Tag "Get"
}

foreach ($registryPath in $registrySearchPaths) {

    if (-not (Test-Path -Path $registryPath)) {
        Write-Log "Registry path '$registryPath' does not exist, skipping." -Tag "Debug"
        continue
    }

    Write-Log "Searching in registry path: $registryPath" -Tag "Get"

    $subKeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue

    if ($null -eq $subKeys -or $subKeys.Count -eq 0) {
        Write-Log "No subkeys found under: $registryPath" -Tag "Debug"
        continue
    }

    Write-Log "Found $($subKeys.Count) subkeys under: $registryPath" -Tag "Debug"

    foreach ($subKey in $subKeys) {

        $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) {
            Write-Log "Could not read properties for key: $($subKey.PSPath)" -Tag "Debug"
            continue
        }

        $displayName    = $properties.DisplayName
        $displayVersion = $properties.DisplayVersion

        if ($displayName) {
            Write-Log "Found product: '$displayName' Version: '$displayVersion'" -Tag "Debug"
        }

        # Use wildcard matching for DisplayName if enabled, otherwise exact match
        # Version is always exact match
        $nameMatch = if ($useWildcardMatching) {
            $displayName -like $applicationName
        } else {
            $displayName -eq $applicationName
        }
        $versionMatch = $displayVersion -eq $applicationVersion

        if ($nameMatch -and $versionMatch) {
            Write-Log "Match found: $displayName ($displayVersion)" -Tag "Success"
            $applicationFound = $true
            break
        }
    }

    if ($applicationFound) {
        Write-Log "Application located. Stopping further registry search." -Tag "Debug"
        break
    }
}

# ===========================[ Script End ]================================

if ($applicationFound) {
    Write-Log "$applicationName Version $applicationVersion is installed." -Tag "Success"
    Stop-Script -ExitCode 0
}
else {
    Write-Log "$applicationName Version $applicationVersion is NOT installed." -Tag "Error"
    Stop-Script -ExitCode 1
}
