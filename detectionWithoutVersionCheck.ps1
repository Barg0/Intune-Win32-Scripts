# ---------------------------[ Script Start Timestamp ]--------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Configuration ]------------------------------
$applicationName = "__REGISTRY_DISPLAY_NAME__"

# ---------------------------[ Registry Configuration ]--------------------------
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) { $applicationName -replace '[\*\?\[\]]', '' } else {
    $applicationName
}

# ---------------------------[ Logging Configuration ]--------------------------
$scriptName       = $applicationNameClean
$logFileName      = "detection.log"
$log              = $true
$logDebug         = $false
$logGet           = $true
$logRun           = $true
$enableLogFile    = $true
$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    try {
        $null = New-Item -ItemType Directory -Path $logFileDirectory -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to create log directory '$logFileDirectory': $($_.Exception.Message)"
    }
}

# ---------------------------[ Logging Function ]------------------------------
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
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ---------------------------[ Exit Function ]--------------------------
function Complete-Script {
    [CmdletBinding()]
    param(
        [int]$exitCode
    )

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Runtime $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit $exitCode" -Tag "Info"
    Write-Log "====================  End  ====================" -Tag "End"

    exit $exitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "====================  Start  ====================" -Tag "Start"
Write-Log "Host $env:COMPUTERNAME | $env:USERNAME | $applicationName" -Tag "Info"

# ---------------------------[ Detection Logic ]------------------------------

$applicationFound = $false

if ($useWildcardMatching) {
    Write-Log "Detect: '$applicationName' (wildcard)" -Tag "Get"
}
else {
    Write-Log "Detect: '$applicationName'" -Tag "Get"
}

foreach ($registryPath in $registrySearchPaths) {

    if (-not (Test-Path -Path $registryPath)) {
        Write-Log "Skip missing: $registryPath" -Tag "Debug"
        continue
    }

    Write-Log "Reg scan: $registryPath" -Tag "Debug"

    $subKeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue

    if ($null -eq $subKeys -or $subKeys.Count -eq 0) {
        Write-Log "No subkeys: $registryPath" -Tag "Debug"
        continue
    }

    Write-Log "Subkeys $($subKeys.Count): $registryPath" -Tag "Debug"

    foreach ($subKey in $subKeys) {

        $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) {
            Write-Log "Unreadable key: $($subKey.PSPath)" -Tag "Debug"
            continue
        }

        $displayName = $properties.DisplayName
        $displayVersion = $properties.DisplayVersion

        if ($displayName) {
            Write-Log "Row: '$displayName'" -Tag "Debug"
        }

        $isMatch = if ($useWildcardMatching) {
            $displayName -like $applicationName
        } else {
            $displayName -eq $applicationName
        }

        if ($isMatch) {
            $matchedKeyPath = Join-Path -Path $registryPath -ChildPath $subKey.PSChildName
            $verPart = if ([string]::IsNullOrWhiteSpace($displayVersion)) { '' } else { " $displayVersion" }
            Write-Log "Detect OK: $displayName$verPart @ $matchedKeyPath" -Tag "Success"
            $applicationFound = $true
            break
        }
    }

    if ($applicationFound) {
        Write-Log "Stop search (found)." -Tag "Debug"
        break
    }
}

if ($applicationFound) {
    Complete-Script -exitCode 0
}
else {
    Write-Log "Detect miss: '$applicationName'" -Tag "Error"
    Complete-Script -exitCode 1
}