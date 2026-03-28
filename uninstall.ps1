# ---------------------------[ Script Start Timestamp ]--------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Configuration ]------------------------------
$applicationName         = "__REGISTRY_DISPLAY_NAME__"
$usePackagedUninstaller  = $false
$installerName           = "setup.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'

# ---------------------------[ UNC Path & Authentication ]---------------------
# Optional: Use when packaged uninstaller is on a network share (Entra-joined devices need creds)
$installerPathOverride = ""   # UNC root only, e.g. "\\server01.domain.tld\software"
$useUncAuth           = $false
$uncCredential        = $null   # $uncCredential = [PSCredential]::new("user@domain.tld", (ConvertTo-SecureString "<-YOUR-PASSWORD->" -AsPlainText -Force))

# ---------------------------[ Paths (computed) ]--------
if (-not [string]::IsNullOrWhiteSpace($installerPathOverride)) {
    $installerPath = Join-Path -Path $installerPathOverride.TrimEnd('\') -ChildPath $installerName
} else {
    $installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName
}

# ---------------------------[ Registry Configuration ]--------------------------
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ File Check Retry Configuration ]------------------
$fileCheckMaxRetries = 5
$fileCheckRetryDelaySeconds = 30

# ---------------------------[ Wildcard Matching Configuration ]-----------------
$useWildcardMatching = $applicationName.Contains('*') -or $applicationName.Contains('?') -or $applicationName.Contains('[') -or $applicationName.Contains(']')
$applicationNameClean = if ($useWildcardMatching) { $applicationName -replace '[\*\?\[\]]', '' } else {
    $applicationName
}

# ---------------------------[ Logging Configuration ]--------------------------
$scriptName       = $applicationNameClean
$logFileName      = "uninstall.log"
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
    if ($tagList -contains $rawTag) { $rawTag = $rawTag.PadRight(7) }
    else { $rawTag = "Error  " }

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

# ---------------------------[ Exit Function ]------------------------------
function Complete-Script {
    [CmdletBinding()]
    param([int]$exitCode)
    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime
    Write-Log "Runtime $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit $exitCode" -Tag "Info"
    Write-Log "====================  End  ====================" -Tag "End"
    exit $exitCode
}

# ---------------------------[ UNC Path Access Function ]-----------------------
function Test-UncPathAccess {
    [CmdletBinding()]
    param(
        [string]$path,
        [bool]$useUncAuth,
        [PSCredential]$uncCredential
    )
    if (-not $path.StartsWith("\\")) { return $true }
    if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
        Write-Log "UNC OK (anonymous)." -Tag "Success"
        return $true
    }
    if (-not $useUncAuth -or -not $uncCredential) {
        Write-Log "UNC blocked; set useUncAuth + uncCredential." -Tag "Error"
        return $false
    }
    $parts = $path.TrimStart('\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) {
        Write-Log "UNC invalid (no share root)." -Tag "Error"
        return $false
    }
    $shareRoot = "\\$($parts[0])\$($parts[1])"
    Write-Log "UNC map: $shareRoot" -Tag "Get"
    try {
        $credUser = $uncCredential.UserName
        $credPass = $uncCredential.GetNetworkCredential().Password
        $netUseResult = net use $shareRoot /user:$credUser $credPass 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "net use failed: $netUseResult" -Tag "Error"
            return $false
        }
        if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
            Write-Log "UNC OK (auth)." -Tag "Success"
            return $true
        }
        Write-Log "UNC still blocked after auth." -Tag "Error"
        return $false
    }
    catch {
        Write-Log "UNC auth error: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

# ---------------------------[ File Path Retry Check Function ]-------------------
function Test-PathWithRetry {
    [CmdletBinding()]
    param(
        [string]$path,
        [int]$maxRetries = 5,
        [int]$retryDelaySeconds = 30
    )

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if (Test-Path -Path $path) {
            if ($attempt -gt 1) {
                Write-Log "Path OK (${attempt}/${maxRetries}): $path" -Tag "Success"
            }
            return $true
        }

        if ($attempt -lt $maxRetries) {
            Write-Log "Missing ${attempt}/${maxRetries}: $path, retry ${retryDelaySeconds}s" -Tag "Info"
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }

    return $false
}

# ---------------------------[ Registry Check Function ]-----------------------
function Test-ApplicationInRegistry {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [switch]$suppressLogging,
        [bool]$useWildcardMatching = $false
    )
    if (-not $suppressLogging) {
        if ($useWildcardMatching) {
            Write-Log "Reg: '$applicationName' (wildcard)" -Tag "Get"
        } else {
            Write-Log "Reg: '$applicationName'" -Tag "Get"
        }
    }
    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Skip missing: $registryPath" -Tag "Debug"
            continue
        }
        $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subkeys) { continue }
        foreach ($subkey in $subkeys) {
            $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }
            $displayName = $properties.DisplayName
            $isMatch = if ($useWildcardMatching) { $displayName -like $applicationName } else { $displayName -eq $applicationName }
            if ($isMatch) {
                $matchedKeyPath = Join-Path -Path $registryPath -ChildPath $subkey.PSChildName
                Write-Log "Reg hit: '$applicationName' @ $matchedKeyPath" -Tag "Debug"
                return $true
            }
        }
    }
    Write-Log "Reg miss: '$applicationName'" -Tag "Debug"
    return $false
}

# ---------------------------[ Post-Uninstall Validation Function ]-------------
function Test-PostUninstallValidation {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [int]$maxRetries = 3,
        [int]$retryDelay = 5,
        [bool]$useWildcardMatching = $false
    )
    Write-Log "Post-uninstall verify..." -Tag "Info"
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "Verify retry ${attempt}/${maxRetries} (${retryDelay}s)" -Tag "Info"
            Start-Sleep -Seconds $retryDelay
        }
        $applicationRemoved = -not (Test-ApplicationInRegistry -applicationName $applicationName -registryPaths $registryPaths -suppressLogging -useWildcardMatching $useWildcardMatching)
        if ($applicationRemoved) {
            Write-Log "Missiing from reg." -Tag "Success"
            return $true
        }
        Write-Log "Still in reg (${attempt}/${maxRetries})." -Tag "Info"
    }
    Write-Log "Verify fail: still in reg after ${maxRetries} tries." -Tag "Error"
    return $false
}

# ---------------------------[ Execute Uninstall Process Function ]-------------
function Invoke-UninstallProcess {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [string]$context = "Uninstall"
    )
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        Write-Log "FilePath empty; skip ${context}." -Tag "Error"
        return $null
    }
    Write-Log "${context}: '$filePath' $argumentList" -Tag "Run"
    try {
        $processParams = @{ FilePath = $filePath; Wait = $true; PassThru = $true; NoNewWindow = $true }
        if (-not [string]::IsNullOrWhiteSpace($argumentList)) { $processParams['ArgumentList'] = $argumentList }
        $process = Start-Process @processParams
        if ($null -eq $process) {
            Write-Log "Start-Process returned no object (${context})." -Tag "Error"
            return $null
        }
    }
    catch {
        Write-Log "${context} start error: $($_.Exception.Message)" -Tag "Error"
        Write-Log "$($_ | Out-String)" -Tag "Debug"
        return $null
    }
    Write-Log "PID $($process.Id) (${context})" -Tag "Debug"
    Write-Log "Exit $($process.ExitCode) (${context})" -Tag "Info"
    return $process
}

# ---------------------------[ Convert UninstallString Function ]---------------
function ConvertFrom-UninstallString {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    $UninstallString = $UninstallString.Trim()
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString empty." -Tag "Error"
        return @{
            FilePath  = ""
            Arguments = ""
        }
    }

    if ($UninstallString -match '^"([^"]+)"\s*(.*)$') {
        $filePath = $matches[1]
        $arguments = $matches[2].Trim()
    }
    elseif ($UninstallString -match '^([^\s"]+\.(exe|msi|bat|cmd))(?:\s+(.*))?$') {
        $filePath = $matches[1]
        $arguments = if ($matches[3]) { $matches[3].Trim() } else { "" }
    }
    else {
        $parts = $UninstallString -split '\s+', 2
        $filePath = $parts[0]
        $arguments = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    }

    if ([string]::IsNullOrWhiteSpace($filePath)) {
        Write-Log "Parse fail UninstallString: $UninstallString" -Tag "Error"
    }

    return @{
        FilePath  = $filePath
        Arguments = $arguments
    }
}

# ---------------------------[ Detect MSI Function ]----------------------------
function Test-IsMsiInstaller {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [string]$uninstallString
    )

    $stringToCheck = $uninstallString
    if ([string]::IsNullOrWhiteSpace($stringToCheck) -and $argumentList) {
        $stringToCheck = $argumentList
    }
    if ([string]::IsNullOrWhiteSpace($stringToCheck) -and $filePath) {
        $stringToCheck = $filePath
    }

    if ($filePath -and $filePath -match 'msiexec\.exe') { return $true }
    if ($filePath -and $filePath -match '\.msi$') { return $true }
    if ($argumentList -and $argumentList -match '(?:^|\s|/)[xi](?:\s|$|\{)') { return $true }
    if ($uninstallString -and $uninstallString -match '(?:^|"|\\|\s)msiexec\.exe(?:\s|"|/|$)') { return $true }
    if ($uninstallString -and $uninstallString -match '\/[iIlLxX]\s*\{[a-fA-F0-9\-]+\}') { return $true }
    if ($uninstallString -and $uninstallString -match '\.msi(?:\s|"|$)') { return $true }

    return $false
}

# ---------------------------[ Find Application Uninstall/Modify Command ]--------
function Get-ApplicationUninstallString {
    [CmdletBinding()]
    param(
        [string]$applicationName,
        [string[]]$registryPaths,
        [string]$excludeUninstallString = $null,
        [bool]$useWildcardMatching = $false
    )

    if ($useWildcardMatching) {
        Write-Log "Find uninstall: '$applicationName' (wildcard)" -Tag "Get"
    } else {
        Write-Log "Find uninstall: '$applicationName'" -Tag "Get"
    }

    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -Path $registryPath)) {
            Write-Log "Skip missing: $registryPath" -Tag "Debug"
            continue
        }

        Write-Log "Reg scan: $registryPath" -Tag "Debug"

        $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $subkeys) {
            Write-Log "No subkeys: $registryPath" -Tag "Debug"
            continue
        }

        foreach ($subkey in $subkeys) {
            $properties = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $properties) { continue }

            $displayName = $properties.DisplayName
            $uninstallString = $properties.UninstallString
            $modifyPath = $properties.ModifyPath

            if ($displayName) {
                Write-Log "Row: '$displayName'" -Tag "Debug"
            }

            $isMatch = if ($useWildcardMatching) {
                $displayName -like $applicationName
            } else {
                $displayName -eq $applicationName
            }

            if (-not $isMatch) { continue }

            $matchedKeyPath = Join-Path -Path $registryPath -ChildPath $subkey.PSChildName
            Write-Log "Found: '$displayName' @ $matchedKeyPath" -Tag "Success"

            if (-not [string]::IsNullOrWhiteSpace($excludeUninstallString)) {
                $currentNormalized = $uninstallString.Trim().ToLowerInvariant()
                $excludeNormalized = $excludeUninstallString.Trim().ToLowerInvariant()
                if ($currentNormalized -eq $excludeNormalized) {
                    Write-Log "Skip UninstallString (excluded exact)." -Tag "Debug"
                    continue
                }
                if ($currentNormalized -match '/[xi]\{([a-f0-9\-]+)\}') {
                    $currentGuid = $matches[1]
                    if ($excludeNormalized -match '/[xi]\{([a-f0-9\-]+)\}') {
                        $excludeGuid = $matches[1]
                        if ($currentGuid -eq $excludeGuid) {
                            Write-Log "Skip UninstallString (excluded MSI code)." -Tag "Debug"
                            continue
                        }
                    }
                }
            }

            $chosenString = Get-BestUninstallCommand -uninstallString $uninstallString -modifyPath $modifyPath
            if (-not [string]::IsNullOrWhiteSpace($chosenString)) {
                return $chosenString
            }

            Write-Log "No UninstallString/ModifyPath for '$displayName'." -Tag "Debug"
        }
    }

    return $null
}

# ---------------------------[ Select Best Uninstall Command ]--------------------
function Get-BestUninstallCommand {
    [CmdletBinding()]
    param(
        [string]$uninstallString,
        [string]$modifyPath
    )

    $uninstallTrimmed = if ($uninstallString) { $uninstallString.Trim() } else { "" }
    $modifyTrimmed = if ($modifyPath) { $modifyPath.Trim() } else { "" }

    $uninstallIsMsi = Test-IsMsiInstaller -uninstallString $uninstallTrimmed
    $modifyIsMsi = Test-IsMsiInstaller -uninstallString $modifyTrimmed

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and $uninstallIsMsi) {
        Write-Log "Use UninstallString (MSI)." -Tag "Info"
        return $uninstallTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and [string]::IsNullOrWhiteSpace($modifyTrimmed)) {
        Write-Log "Use UninstallString (no ModifyPath)." -Tag "Info"
        return $uninstallTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not $uninstallIsMsi -and -not [string]::IsNullOrWhiteSpace($modifyTrimmed) -and $modifyIsMsi) {
        Write-Log "UninstallString non-MSI; use ModifyPath (MSI)." -Tag "Info"
        return $modifyTrimmed
    }

    if (-not [string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not $uninstallIsMsi -and (-not [string]::IsNullOrWhiteSpace($modifyTrimmed) -and -not $modifyIsMsi)) {
        Write-Log "ModifyPath non-MSI; fallback UninstallString." -Tag "Info"
        return $uninstallTrimmed
    }

    if ([string]::IsNullOrWhiteSpace($uninstallTrimmed) -and -not [string]::IsNullOrWhiteSpace($modifyTrimmed)) {
        if ($modifyIsMsi) {
            Write-Log "UninstallString empty; ModifyPath (MSI)." -Tag "Info"
        } else {
            Write-Log "UninstallString empty; ModifyPath last resort." -Tag "Info"
        }
        return $modifyTrimmed
    }

    return $null
}

# ---------------------------[ Resolve System Executable Function ]-------------
function Resolve-SystemExecutable {
    [CmdletBinding()]
    param(
        [string]$ExecutableName
    )

    if ([System.IO.Path]::IsPathRooted($ExecutableName) -and (Test-Path -Path $ExecutableName)) {
        return $ExecutableName
    }

    $fileName = [System.IO.Path]::GetFileName($ExecutableName)
    $fileNameLower = $fileName.ToLowerInvariant()

    if ($fileNameLower -eq "msiexec.exe") {
        $system32Path = Join-Path -Path $env:SystemRoot -ChildPath "System32\msiexec.exe"
        if (Test-Path -Path $system32Path) {
            Write-Log "Resolve '$ExecutableName' -> $system32Path" -Tag "Debug"
            return $system32Path
        }
        $syswow64Path = Join-Path -Path $env:SystemRoot -ChildPath "SysWOW64\msiexec.exe"
        if (Test-Path -Path $syswow64Path) {
            Write-Log "Resolve '$ExecutableName' -> $syswow64Path" -Tag "Debug"
            return $syswow64Path
        }
    }

    try {
        $command = Get-Command -Name $fileName -ErrorAction Stop
        if ($command -and $command.Source) {
            Write-Log "Resolve '$ExecutableName' PATH -> $($command.Source)" -Tag "Debug"
            return $command.Source
        }
    }
    catch {
        Write-Log "Get-Command miss '$fileName'; keep path." -Tag "Debug"
    }
    return $ExecutableName
}

# ---------------------------[ Process UninstallString Function ]---------------
function Get-ProcessedUninstallerCommand {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        Write-Log "UninstallString empty." -Tag "Error"
        return $null
    }

    Write-Log "UninstallString raw: $UninstallString" -Tag "Debug"
    $uninstallString = $uninstallString.Trim()
    $isMsi = Test-IsMsiInstaller -UninstallString $uninstallString

    if ($isMsi) {
        Write-Log "MSI uninstaller; ensure quiet args." -Tag "Debug"

        # ModifyPath often has /i or /I (install); we need /X (uninstall). Also handle /l (font/typo for I).
        if ($uninstallString -match '/[iIlL]\s*\{([a-fA-F0-9\-]+)\}') {
            $productCode = $matches[1]
            $uninstallString = $uninstallString -replace '/[iIlL]\s*\{', '/X{'
            Write-Log "MSI /I -> /X (code $productCode)" -Tag "Info"
        }
        # MSI path format: /i "path\to\file.msi" -> /x for uninstall
        elseif ($uninstallString -match '/[iIlL]\s+"') {
            $uninstallString = $uninstallString -replace '/([iIlL])\s+', '/x '
            Write-Log "MSI /I -> /X (path)" -Tag "Info"
        }

        if ($uninstallString -notmatch '/(?:qn|quiet|q|norestart)(?:\s|$|/)') {
            $uninstallString += " $uninstallerArgumentsMsi"
            Write-Log "+ MSI args: $uninstallerArgumentsMsi" -Tag "Debug"
        }
        else {
            Write-Log "MSI string already quiet." -Tag "Debug"
        }
    }
    else {
        Write-Log "EXE uninstaller; check args." -Tag "Info"
        $existingArgs = $uninstallString -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        $providedArgs = $uninstallerArgumentsExe -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() }
        $argsToAppend = @()
        foreach ($arg in $providedArgs) {
            if ($existingArgs -contains $arg) {
                Write-Log "Arg '$arg' already in string; skip." -Tag "Debug"
            }
            else {
                $argsToAppend += $arg
            }
        }
        
        if ($argsToAppend.Count -gt 0) {
            $argsToAppendString = $argsToAppend -join ' '
            $uninstallString += " $argsToAppendString"
            Write-Log "+ EXE args: $argsToAppendString" -Tag "Debug"
        }
        else {
            Write-Log "EXE args already present; no append." -Tag "Debug"
        }
    }

    Write-Log "UninstallString final: $uninstallString" -Tag "Debug"
    $parsedUninstall = ConvertFrom-UninstallString -UninstallString $uninstallString
    $uninstallerPath = $parsedUninstall.FilePath
    $uninstallerArgs = $parsedUninstall.Arguments

    if ([string]::IsNullOrWhiteSpace($uninstallerPath)) {
        Write-Log "Parse fail: no exe from UninstallString." -Tag "Error"
        return $null
    }

    if ($uninstallerPath -match '\.msi$') {
        $uninstallerPath = [System.Environment]::ExpandEnvironmentVariables($uninstallerPath)
        if (-not (Test-PathWithRetry -path $uninstallerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
            Write-Log "MSI missing: $uninstallerPath" -Tag "Error"
            return $null
        }
        $escapedPath = $uninstallerPath -replace '"', '""'
        $uninstallerPath = Resolve-SystemExecutable -ExecutableName "msiexec.exe"
        $uninstallerArgs = "/x `"$escapedPath`" $uninstallerArgumentsMsi"
        Write-Log "MSI file -> msiexec /x" -Tag "Info"
    }
    else {
        $uninstallerPath = [System.Environment]::ExpandEnvironmentVariables($uninstallerPath)
        $uninstallerPath = Resolve-SystemExecutable -ExecutableName $uninstallerPath

        if (-not (Test-PathWithRetry -path $uninstallerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
            Write-Log "Uninstaller missing: $uninstallerPath" -Tag "Error"
            return $null
        }
    }

    Write-Log "Parsed exe: $uninstallerPath" -Tag "Debug"
    Write-Log "Parsed args: $uninstallerArgs" -Tag "Debug"

    $isMsiFinal = Test-IsMsiInstaller -FilePath $uninstallerPath -ArgumentList $uninstallerArgs

    return @{
        FilePath  = $uninstallerPath
        Arguments = $uninstallerArgs
        IsMsi     = $isMsiFinal
    }
}

# ---------------------------[ Execute Uninstall with Validation Function ]-----
function Invoke-UninstallWithValidation {
    [CmdletBinding()]
    param(
        [string]$filePath,
        [string]$argumentList,
        [bool]$isMsi,
        [string]$applicationName,
        [string[]]$registryPaths,
        [string]$context = "Uninstall",
        [string]$originalUninstallString = $null,
        [bool]$useWildcardMatching = $false
    )

    try {
        $process = Invoke-UninstallProcess -filePath $filePath -argumentList $argumentList -context $context

        if ($null -eq $process) {
            return @{ Success = $false; ExitCode = 1 }
        }

        $isSuccessCode = $process.ExitCode -eq 0 -or ($isMsi -and $process.ExitCode -eq 3010)

        if ($isSuccessCode) {
            if ($process.ExitCode -eq 3010) {
                Write-Log "Uninstall OK; reboot 3010." -Tag "Info"
            }
            else {
                Write-Log "Uninstall exit $($process.ExitCode): $applicationName" -Tag "Success"
            }

            $validationParams = @{
                applicationName       = $applicationName
                registryPaths         = $registryPaths
                useWildcardMatching   = $useWildcardMatching
            }
            $validationSuccess = Test-PostUninstallValidation @validationParams

            if ($validationSuccess) {
                return @{ Success = $true; ExitCode = $process.ExitCode }
            }
            else {
                Write-Log "Uninstall OK but verify failed." -Tag "Error"
                
                Write-Log "Fallback: alt UninstallString..." -Tag "Info"
                
                if ([string]::IsNullOrWhiteSpace($originalUninstallString)) {
                    Write-Log "No original UninstallString; no fallback." -Tag "Error"
                    return @{ Success = $false; ExitCode = 1 }
                }

                $alternativeParams = @{
                    applicationName         = $applicationName
                    registryPaths           = $registryPaths
                    excludeUninstallString  = $originalUninstallString
                    useWildcardMatching     = $useWildcardMatching
                }
                $alternativeUninstallString = Get-ApplicationUninstallString @alternativeParams
                
                if (-not [string]::IsNullOrWhiteSpace($alternativeUninstallString)) {
                    Write-Log "Alt UninstallString; run fallback." -Tag "Info"
                    Write-Log "Alt string: $alternativeUninstallString" -Tag "Debug"
                    
                    $fallbackCommand = Get-ProcessedUninstallerCommand -UninstallString $alternativeUninstallString
                    
                    if ($null -ne $fallbackCommand) {
                        Write-Log "Fallback uninstall..." -Tag "Run"
                        $fallbackProcessParams = @{
                            filePath      = $fallbackCommand.FilePath
                            argumentList  = $fallbackCommand.Arguments
                            context       = "Fallback uninstall"
                        }
                        $fallbackProcess = Invoke-UninstallProcess @fallbackProcessParams
                        
                        if ($null -ne $fallbackProcess) {
                            $fallbackSuccessCode = $fallbackProcess.ExitCode -eq 0 -or ($fallbackCommand.IsMsi -and $fallbackProcess.ExitCode -eq 3010)
                            
                            if ($fallbackSuccessCode) {
                                Write-Log "Fallback exit $($fallbackProcess.ExitCode)" -Tag "Success"
                                
                                Write-Log "Re-verify after fallback..." -Tag "Info"
                                $fallbackValidationParams = @{
                                    applicationName       = $applicationName
                                    registryPaths         = $registryPaths
                                    useWildcardMatching   = $useWildcardMatching
                                }
                                $fallbackValidationSuccess = Test-PostUninstallValidation @fallbackValidationParams
                                
                                if ($fallbackValidationSuccess) {
                                    Write-Log "Fallback + verify OK." -Tag "Success"
                                    return @{ Success = $true; ExitCode = $fallbackProcess.ExitCode }
                                }
                                else {
                                    Write-Log "Fallback OK; verify still fail." -Tag "Error"
                                    return @{ Success = $false; ExitCode = 1 }
                                }
                            }
                            else {
                                Write-Log "Fallback exit $($fallbackProcess.ExitCode) (fail)" -Tag "Error"
                                return @{ Success = $false; ExitCode = 1 }
                            }
                        }
                        else {
                            Write-Log "Fallback start failed." -Tag "Error"
                            return @{ Success = $false; ExitCode = 1 }
                        }
                    }
                    else {
                        Write-Log "Alt UninstallString parse fail." -Tag "Error"
                        return @{ Success = $false; ExitCode = 1 }
                    }
                }
                else {
                    Write-Log "No alt UninstallString." -Tag "Error"
                    return @{ Success = $false; ExitCode = 1 }
                }
            }
        }
        else {
            Write-Log "${context} exit $($process.ExitCode) (fail)" -Tag "Error"
            return @{ Success = $false; ExitCode = $process.ExitCode }
        }
    }
    catch {
        Write-Log "${context} error: $($_.Exception.Message)" -Tag "Error"
        Write-Log "$($_ | Out-String)" -Tag "Debug"
        return @{ Success = $false; ExitCode = 1 }
    }
}

# ---------------------------[ Prepare Packaged Uninstaller Function ]----------
function Get-PackagedUninstallerCommand {
    [CmdletBinding()]
    param(
        [string]$InstallerPath
    )

    $installerExtension = [System.IO.Path]::GetExtension($InstallerPath)
    Write-Log "Packaged ext: '$installerExtension'" -Tag "Debug"

    switch ($installerExtension.ToLowerInvariant()) {
        ".msi" {
            Write-Log "Packaged MSI -> msiexec /x" -Tag "Info"
            $filePath = "msiexec.exe"
            # Escape quotes in path if present, then quote the entire path
            $escapedPath = $InstallerPath -replace '"', '""'
            $argumentList = "/x `"$escapedPath`" $uninstallerArgumentsMsi"
            $isMsi = $true
        }
        ".exe" {
            Write-Log "Packaged EXE + EXE args" -Tag "Info"
            $filePath = $InstallerPath
            $argumentList = $uninstallerArgumentsExe
            $isMsi = $false
        }
        default {
            Write-Log "Unsupported ext '$installerExtension' (need .exe/.msi)." -Tag "Error"
            return $null
        }
    }

    Write-Log "Pkg file: $filePath" -Tag "Debug"
    Write-Log "Pkg args: $argumentList" -Tag "Debug"

    return @{
        FilePath  = $filePath
        Arguments = $argumentList
        IsMsi     = $isMsi
    }
}

# ---------------------------[ Script Start ]-----------------------------------
Write-Log "====================  Start  ====================" -Tag "Start"
Write-Log "Host $env:COMPUTERNAME | $env:USERNAME | $applicationName" -Tag "Info"

if ([string]::IsNullOrWhiteSpace($applicationName)) {
    Write-Log "Set `$applicationName." -Tag "Error"
    Complete-Script -exitCode 1
}

if ($usePackagedUninstaller) {

    if (-not (Test-UncPathAccess -path $installerPath -useUncAuth $useUncAuth -uncCredential $uncCredential)) {
        Complete-Script -exitCode 1
    }

    if (-not (Test-PathWithRetry -path $installerPath -maxRetries $fileCheckMaxRetries -retryDelaySeconds $fileCheckRetryDelaySeconds)) {
        Write-Log "Packaged installer missing: $installerPath" -Tag "Error"
        Complete-Script -exitCode 1
    }

    Write-Log "Packaged installer: $installerPath" -Tag "Success"

    $uninstallerCommand = Get-PackagedUninstallerCommand -InstallerPath $installerPath
    if ($null -eq $uninstallerCommand) {
        Complete-Script -exitCode 1
    }

    $uninstallParams = @{
        filePath              = $uninstallerCommand.FilePath
        argumentList          = $uninstallerCommand.Arguments
        isMsi                 = $uninstallerCommand.IsMsi
        applicationName       = $applicationName
        registryPaths         = $registrySearchPaths
        context               = "Packaged uninstall"
        useWildcardMatching   = $useWildcardMatching
    }
    $result = Invoke-UninstallWithValidation @uninstallParams

    Complete-Script -exitCode $result.ExitCode
}
else {

    $uninstallString = Get-ApplicationUninstallString -ApplicationName $applicationName -registryPaths $registrySearchPaths -useWildcardMatching $useWildcardMatching

    if ($null -eq $uninstallString) {
        Write-Log "No uninstall cmd: '$applicationName' (reg miss or empty string)." -Tag "Error"
        Complete-Script -exitCode 1
    }

    $uninstallerCommand = Get-ProcessedUninstallerCommand -UninstallString $uninstallString
    if ($null -eq $uninstallerCommand) {
        Complete-Script -exitCode 1
    }

    $uninstallParams = @{
        filePath                  = $uninstallerCommand.FilePath
        argumentList              = $uninstallerCommand.Arguments
        isMsi                     = $uninstallerCommand.IsMsi
        applicationName           = $applicationName
        registryPaths             = $registrySearchPaths
        context                   = "Registry-based uninstall"
        originalUninstallString   = $uninstallString
        useWildcardMatching       = $useWildcardMatching
    }
    $result = Invoke-UninstallWithValidation @uninstallParams

    Complete-Script -exitCode $result.ExitCode
}