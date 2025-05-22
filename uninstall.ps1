# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName = "Uninstall - 3CXPhone for Windows"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true
$logFileDirectory = "$env:ProgramData\N-AbleLogs\Applications\$scriptName"
$logFile = "$logFileDirectory\uninstall.log"

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
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Parameters ]---------------------------
$targetDisplayName = "3CXPhone for Windows"

# ---------------------------[ Registry Paths ]---------------------------
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Uninstall Routine ]---------------------------
$uninstalled = $false

foreach ($path in $registryPaths) {
    $subkeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
    foreach ($subkey in $subkeys) {
        try {
            $props = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $props.DisplayName -and $props.DisplayName -eq $targetDisplayName) {
                Write-Log "Found '$targetDisplayName' in registry path $($subkey.PSPath)" -Tag "Check"

                if ($null -ne $props.QuietUninstallString) {
                    $cmd = $props.QuietUninstallString
                    Write-Log "Using QuietUninstallString: $cmd" -Tag "Info"
                } elseif ($null -ne $props.UninstallString) {
                    $cmd = $props.UninstallString
                    if ($cmd -match "msiexec\.exe") {
                        $cmd += " /qn"
                        Write-Log "Using MSI uninstall string (modified for silent): $cmd" -Tag "Info"
                    } else {
                        $cmd += " /quiet"
                        Write-Log "Using EXE uninstall string (modified for silent): $cmd" -Tag "Info"
                    }
                } else {
                    Write-Log "No uninstall command found for $targetDisplayName" -Tag "Error"
                    Complete-Script -ExitCode 1
                }

                # Run the uninstall
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "$cmd" -Wait -NoNewWindow
                Write-Log "Uninstall command executed successfully." -Tag "Success"
                $uninstalled = $true
                break
            }
        } catch {
            Write-Log "Error processing $($subkey.PSChildName): $_" -Tag "Error"
        }
    }

    if ($uninstalled) { break }
}

if (-not $uninstalled) {
    Write-Log "Application '$targetDisplayName' not found in any uninstall registry path." -Tag "Error"
    Complete-Script -ExitCode 1
}

Complete-Script -ExitCode 0
