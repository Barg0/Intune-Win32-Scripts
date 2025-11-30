# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date


# ---------------------------[ Configuration ]---------------------------
# Language/region this Win32 app instance is responsible for (e.g. "fr-BE")
$languageCode  = "nl-NL"


# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Windows Language Pack $($languageCode)"
$logFileName = "detection.log"


# ---------------------------[ Logging Setup ]---------------------------
# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $true for verbose DEBUG logging
$logGet        = $true    # enable/disable all [Get] logs
$logRun        = $true    # enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}


# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$Message,
        [string]$Tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches (optional – if you want these)
    if ($Tag -eq "Debug" -and -not $logDebug) { return }
    if ($Tag -eq "Get"   -and -not $logGet)   { return }
    if ($Tag -eq "Run"   -and -not $logRun)   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $Tag.Trim()

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

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($enableLogFile) {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    }

    # Console output
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

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}


# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | App: $scriptName" -Tag "Info"


# ---------------------------[ Constants ]---------------------------
$rootPath          = "HKLM:\SOFTWARE\IntuneCustomReg"
$languagesRootPath = Join-Path $rootPath "Languages"


# ---------------------------[ System Context Validation ]---------------------------
function Test-IsSystemContext {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $sid = $identity.User.Value
        Write-Log "Current process SID: $sid" -Tag "Debug"
        return ($sid -eq "S-1-5-18")
    }
    catch {
        Write-Log "Failed to determine SYSTEM context: $_" -Tag "Error"
        Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
        return $false
    }
}

Write-Log "Validating that detection is running as SYSTEM" -Tag "Get"
if (-not (Test-IsSystemContext)) {
    Write-Log "Detection should run under SYSTEM context. Continuing anyway, but results may be unreliable." -Tag "Info"
}


# ---------------------------[ Detection Logic ]---------------------------
Write-Log "Starting detection for language marker '$languageCode'" -Tag "Info"

if (-not (Test-Path -Path $rootPath)) {
    Write-Log "Root key $rootPath does not exist. Intune language configuration not present." -Tag "Info"
    Complete-Script -ExitCode 1
}

if (-not (Test-Path -Path $languagesRootPath)) {
    Write-Log "Languages key $languagesRootPath does not exist. No language markers present." -Tag "Info"
    Complete-Script -ExitCode 1
}

try {
    Write-Log "Getting properties from $languagesRootPath" -Tag "Get"
    $languagesProps = Get-ItemProperty -Path $languagesRootPath -ErrorAction Stop

    $propNames = $languagesProps.PSObject.Properties |
                 Where-Object { $_.Name -notlike "PS*" } |
                 Select-Object -ExpandProperty Name

    Write-Log "Languages properties present: $($propNames -join ', ')" -Tag "Debug"

    $value = $languagesProps.$languageCode

    if ($null -eq $value) {
        Write-Log "No property for '$languageCode' found under $languagesRootPath" -Tag "Info"
        Complete-Script -ExitCode 1
    }

    $valueString = $value.ToString()
    Write-Log "Detected marker value for '$languageCode' is '$valueString'" -Tag "Debug"

    if ($valueString.ToLower() -eq "true") {
        Write-Log "Language '$languageCode' is marked as installed (value = 'true')" -Tag "Success"
        Complete-Script -ExitCode 0
    } else {
        Write-Log "Language '$languageCode' marker exists but value is not 'true' (value = '$valueString')" -Tag "Info"
        Complete-Script -ExitCode 1
    }
}
catch {
    Write-Log "Failed to read or interpret $languagesRootPath for detection: $_" -Tag "Error"
    Write-Log "Exception detail: $($_ | Out-String)" -Tag "Debug"
    Complete-Script -ExitCode 1
}
