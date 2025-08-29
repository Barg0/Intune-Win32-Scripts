# ---------------------------[ Script Metadata ]---------------------------

# Script version:   2025-07-07
# Script author:    Barg0

# ---------------------------[ Parameter ]---------------------------

$targetDisplayName = "Advanced Monitoring Agent"
$UninstallArguments = "/s"  # Optional arguments for non-MSI uninstallers

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Script Start Timestamp ]---------------------------

$scriptStartTime = Get-Date

# ---------------------------[ Log Controll ]---------------------------

$log = $true
$enableLogFile = $true

# ---------------------------[ Log File/Folder ]---------------------------

$applicationName = "Advanced Monitoring Agent"
$logFileName = "uninstall.log"

$logFileDirectory = "$env:ProgramData\IntuneLogs\Applications\$applicationName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Log Function ]---------------------------

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
        "Debug"   { "DarkYellow"}
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

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
    Write-Log "======== Remediation Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Remediation Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $applicationName" -Tag "Info"

# ---------------------------[ Find and Uninstall Application ]---------------------------

$found = $false

foreach ($path in $registryPaths) {
    Write-Log "Searching in: $path" -Tag "Check"
    $subkeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue

    foreach ($subkey in $subkeys) {
        $displayName = (Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue).DisplayName

        if ($displayName -and $displayName -eq $targetDisplayName) {
            $found = $true
            $uninstallString = (Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue).UninstallString

            if (-not $uninstallString) {
                Write-Log "UninstallString not found for '$targetDisplayName'." -Tag "Error"
                Complete-Script -ExitCode 1
            }

            Write-Log "Found app: $displayName" -Tag "Success"
            Write-Log "Original UninstallString: $uninstallString" -Tag "Debug"

            # Handle MSI uninstallers
            if ($uninstallString -match "msiexec\.exe") {
                Write-Log "Detected MSI-based uninstaller. Appending /qn" -Tag "Info"
                if ($uninstallString -notmatch "/qn") {
                    $uninstallString += " /qn"
                }
            } else {
                Write-Log "Non-MSI uninstaller detected. Appending custom arguments: $UninstallArguments" -Tag "Info"
                $uninstallString += " $UninstallArguments"
            }

            Write-Log "Final UninstallString: $uninstallString" -Tag "Debug"

            try {
                Write-Log "Starting uninstall process..." -Tag "Info"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString`"" -Wait -NoNewWindow
                Write-Log "Uninstall completed." -Tag "Success"
                Complete-Script -ExitCode 0
            } catch {
                Write-Log "Uninstall failed: $_" -Tag "Error"
                Complete-Script -ExitCode 1
            }
        }
    }
}

if (-not $found) {
    Write-Log "Application with DisplayName '$targetDisplayName' not found in registry." -Tag "Error"
    Complete-Script -ExitCode 1
}
