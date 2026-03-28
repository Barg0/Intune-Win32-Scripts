# 🚀 Win32 App Deployment Framework for Microsoft Intune

This repository provides a **reusable, configurable, and standardized PowerShell deployment framework** for packaging, installing, uninstalling, and detecting Win32 applications in **Microsoft Intune**. 🎯

✅ Supports **EXE & MSI installers**
✅ **Logging** to console and under ProgramData (tunable per script)
✅ Registry **or** packaged uninstaller support
✅ Post-installation verification via registry detection
✅ Comprehensive error handling and retry logic

You can deploy **any Win32 application** by modifying just a few variables at the top of each 📜 script.

---
> [!NOTE]
> **Before packaging your application, you SHOULD rename the script files:**
>
> | 📜 Original Template File | ➡️ Rename To | 📝 When To Use |
> |-------------------------|--------------|----------------|
> | `installExe.ps1` | `install.ps1` | When packaging an **EXE installer** |
> | `installMsi.ps1` | `install.ps1` | When packaging an **MSI installer** |
> | `detectionWithVersionCheck.ps1` | `detection.ps1` | When you need **version-specific** detection |
> | `detectionWithoutVersionCheck.ps1` | `detection.ps1` | When you only need **presence** detection |
>
> **Example workflow:**
> 1. If your installer is `MyApp.exe` → Copy `installExe.ps1` and rename it to `install.ps1`
> 2. If your installer is `MyApp.msi` → Copy `installMsi.ps1` and rename it to `install.ps1`
> 3. Choose the appropriate detection script and rename it to `detection.ps1`:
>    - Use `detectionWithVersionCheck.ps1` if you need version checking
>    - Use `detectionWithoutVersionCheck.ps1` if you only need presence detection
> 4. Configure the variables in `install.ps1`, `uninstall.ps1`, and `detection.ps1` (application name, installer name, arguments, etc.)
> 5. Package `install.ps1` and `uninstall.ps1` together using the IntuneWinAppUtil tool
> 6. Upload `detection.ps1` separately in Intune under Detection rules
>
> **Note:** Only ONE `install.ps1` file should be included in your package (either for EXE or MSI, not both). Only ONE `detection.ps1` file should be uploaded to Intune (choose based on your detection requirements).

---

## 📜 Included PowerShell Scripts

| 📜 Script Name                     | 📄 Purpose                                               |
| ---------------------------------- | -------------------------------------------------------- |
| `installExe.ps1` / `installMsi.ps1` | Installs the packaged EXE or MSI silently (rename to `install.ps1` before packaging) |
| `uninstall.ps1`                    | Removes the application (packaged or registry uninstall) |
| `detectionWithVersionCheck.ps1`    | Detects application **and** version via registry (rename to `detection.ps1` before uploading) |
| `detectionWithoutVersionCheck.ps1` | Detects application via `DisplayName` only (rename to `detection.ps1` before uploading) |

> 🔍 **Note:** Detection 📜 scripts are **not** packaged into the `.intunewin` file. They are uploaded separately in Intune under **Detection rules** as `detection.ps1`.

---

## ⚙️ Installation Scripts Overview 📜

### 🎯 Purpose

Silently installs an EXE or MSI included inside the Intune Win32 package with automatic post-installation verification.

### `$applicationVersion` in the install scripts (`installExe.ps1` / `installMsi.ps1`)

Use the same **exact** `DisplayVersion` string as in the uninstall registry (align it with `detectionWithVersionCheck.ps1` when you use that for Intune detection). The scripts do **not** parse semver or decide “newer/older”—only string equality.

**1. Before install** (installer file found; registry queried first):

| `$applicationVersion` | What happens |
| --------------------- | ------------ |
| **Non-empty** | If a matching uninstall row already has this `DisplayName` + `DisplayVersion`, the script **exits `0` and does not run setup**. If `$createShortcuts` is `$true`, shortcuts are still processed before exit. |
| **Empty** (`""`) | Setup **always runs** (no skip). If the name is already registered, the script logs the existing `DisplayVersion` and continues. |

**2. After install** (verification with retries):

| `$applicationVersion` | Success means |
| --------------------- | ------------- |
| **Non-empty** | A row matches `$applicationName` **and** `DisplayVersion` equals `$applicationVersion`. |
| **Empty** (`""`) | A row matches `$applicationName` only (`DisplayVersion` ignored). |

Wildcards in `$applicationName` use the same rules as uninstall/detection (`-like` when the pattern contains wildcard characters). Prefer an **exact** `DisplayName` if you rely on the “already installed → skip” path.

### 📜 `installExe.ps1` - EXE Installer Script

#### 🔧 Parameters (top of `installExe.ps1`)

Edit the **Configuration**, **UNC Path & Authentication**, and **Logging** sections at the top of the script. Typical values are shown in the **Configuration examples** below.

| Variable | Purpose |
| -------- | ------- |
| `$applicationName` | Exact registry `DisplayName` for verification and detection. Must match post-install. |
| `$applicationVersion` | Optional. See **`$applicationVersion` in the install scripts** above (skip-before-install + post-install verification). |
| `$installerName` | Filename of your EXE (e.g. `setup.exe`). Must be in same folder as script. |
| `$installerArgumentsExe` | Arguments passed to the EXE. See below for common values. |
| `$createShortcuts` | `$true` to create shortcuts after install; `$false` to skip. |
| `$desktopShortcuts` | Array of shortcut hashtables for Public Desktop. See Shortcut Configuration. |
| `$startMenuShortcuts` | Array of shortcut hashtables for All Users Start Menu. See Shortcut Configuration. |
| `$registrySearchPaths` | Registry paths for post-install verification. Default covers 64-bit and 32-bit apps. |
| `$log`, `$logDebug`, `$logGet`, `$logRun`, `$enableLogFile` | Logging switches. See Logging section. |

**UNC Path & Authentication** (optional):

| Variable | Purpose |
| -------- | ------- |
| `$installerPathOverride` | UNC root only (e.g. `\\server\software`). When set, path = `$installerPathOverride` + `$installerName`. |
| `$useUncAuth` | `$true` to use credentials when UNC access fails without auth. |
| `$uncCredential` | `[PSCredential]` for UNC auth. Example below—note the **two** closing `)` at the end (one ends `ConvertTo-SecureString`, one ends `::new`). Requires **PowerShell 7+** (`pwsh`) for `-AsPlainText -Force`. |

> `$installerPath` is computed: if `$installerPathOverride` is set → UNC root + `$installerName`; else → script folder + `$installerName`.

**`$installerArgumentsExe` – Common values:**

- **Native EXE:** `/silent`, `/quiet`, `/S`, or vendor-specific flags (check vendor docs).
- **EXE-wrapped MSI:** `'/s /v"/qn"'` or `'/s /v"/qn /norestart"'` – the EXE extracts and runs the MSI; `/s` is silent, `/v` passes args to msiexec.
- **No arguments:** Use `""` when the installer reads silent config from a `.ini` or config file in the same folder. The EXE is run with no command-line arguments.
- Test manually first: `setup.exe /silent` in an elevated prompt to confirm the correct flags.

#### 📋 Configuration examples

**Scenario A: Native EXE, no shortcuts** (e.g. 7-Zip, Notepad++)

```powershell
$applicationName       = "7-Zip 24.08"
$applicationVersion    = ""
$installerName         = "7z2408-x64.exe"
$installerArgumentsExe = '/S'
$createShortcuts       = $false
$desktopShortcuts      = @()
$startMenuShortcuts    = @()
```

**Scenario B: Native EXE with shortcuts** (installer does not create shortcuts in SYSTEM context)

```powershell
$applicationName       = "My Application"
$applicationVersion    = ""
$installerName         = "MyAppSetup.exe"
$installerArgumentsExe = '/silent'
$createShortcuts       = $true
$desktopShortcuts      = @(
    @{ Name = "My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
$startMenuShortcuts    = @(
    @{ Name = "MyApp\My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
```

**Scenario C: EXE-wrapped MSI** (EXE extracts and runs MSI internally)

```powershell
$applicationName       = "Vendor App"
$applicationVersion    = ""
$installerName         = "VendorSetup.exe"
$installerArgumentsExe = '/s /v"/qn /norestart"'
$createShortcuts       = $false
$desktopShortcuts      = @()
$startMenuShortcuts    = @()
```

**Scenario D: App with wildcard DisplayName** (e.g. innovaphone myApps, Citrix Workspace)

```powershell
$applicationName       = "innovaphone myApps*"
$applicationVersion    = ""
$installerName         = "myApps-1510655.exe"
$installerArgumentsExe = '/silent'
$createShortcuts       = $false
$desktopShortcuts      = @()
$startMenuShortcuts    = @()
```

**Scenario D2: EXE with INI-based silent config** (no command-line args needed)

Some installers read silent switches from a `.ini` or config file in the same folder. Package the EXE and the config file together; set arguments to empty so the installer runs with no args:

```powershell
$applicationName       = "My Application"
$applicationVersion    = ""
$installerName         = "setup.exe"
$installerArgumentsExe = ""   # No args – installer reads silent config from .ini
$createShortcuts       = $false
$desktopShortcuts      = @()
$startMenuShortcuts    = @()
```

**Scenario E: Installer on UNC share** (e.g. Entra-joined devices, installers on `\\server\software`)

```powershell
$applicationName       = "My Application"
$applicationVersion    = ""
$installerName         = "installer.exe"   # always used – appended to UNC root
$installerArgumentsExe = '/silent'
$createShortcuts       = $false
$desktopShortcuts      = @()
$startMenuShortcuts    = @()

# UNC section
$installerPathOverride = "\\server01.domain.tld\software"   # UNC root only
$useUncAuth           = $true
$uncCredential        = [PSCredential]::new("svc.intune-install@domain.tld", (ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force))
```

> **Syntax:** `[PSCredential]::new("user", (ConvertTo-SecureString "pass" -AsPlainText -Force))` must end with `))`. A single `)` causes a parser error. Use straight ASCII `"` quotes, not “smart” quotes.

> Result: `$installerPath` = `\\server01.domain.tld\software\installer.exe`. The script tries access without auth first (works for domain-joined); if that fails, uses `net use` with the provided credentials.

#### 📝 Configuration Guide

**`$installerName` - Installer File Name**

Set `$installerName` to the **exact filename** of your installer file (including the extension). This file must be included in the same folder as the script when packaging.

* ✅ **Correct:** `$installerName = "MyApplication-v2.1.0.exe"` (matches the actual filename)
* ✅ **Correct:** `$installerName = "setup.exe"` (if your installer is named `setup.exe`)
* ❌ **Incorrect:** `$installerName = "installer"` (missing file extension)
* ❌ **Incorrect:** `$installerName = "C:\Path\To\Installer.exe"` (should only be the filename, not the full path)

**`$applicationName` - Registry DisplayName**

The `$applicationName` variable must match the **exact `DisplayName`** value from the Windows registry after installation. This is used for:
- Post-installation verification
- Detection scripts
- Uninstall registry lookup

**How to find the DisplayName:**

1. **Method 1: Using Add/Remove Programs (appwiz.cpl)** ⭐ **Easiest Method**
   - Press `Win + R`, type `appwiz.cpl`, press Enter
   - Find your application in the list
   - **Write down the exact name** as it appears (including spaces, capitalization, and special characters)
   - If you need the version, look at the "Version" column (if visible) or right-click the column headers and enable "Version" column
   - This name matches the registry `DisplayName` exactly

2. **Method 2: Using Registry Editor (regedit.exe)**
   - Press `Win + R`, type `regedit`, press Enter
   - Navigate to: `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
   - **Also check:** `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
     - Some 32-bit applications register in the WOW6432Node path on 64-bit systems
   - Browse through the subkeys (GUIDs or product codes)
   - Look for the `DisplayName` value that matches your application
   - Copy the **exact** value (case-sensitive)

3. **Method 3: Using PowerShell (on a test machine with the app installed)**
   ```powershell
   # Check both registry paths
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*YourAppName*" } | 
       Select-Object DisplayName, DisplayVersion
   
   Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*YourAppName*" } | 
       Select-Object DisplayName, DisplayVersion
   ```

**Important:** The `DisplayName` must match **exactly** (case-sensitive, including spaces and special characters).

> [!TIP]
> **Wildcard Support:** If your application's `DisplayName` changes with version numbers (e.g., "innovaphone myApps 1510655"), you can use wildcard matching by adding a `*` to the end of `$applicationName`:
> 
> ```powershell
> $applicationName = "innovaphone myApps*"
> ```
> 
> This will match any `DisplayName` that starts with "innovaphone myApps" (e.g., "innovaphone myApps 1510655", "innovaphone myApps 1510656", etc.). The wildcard characters (`*`, `?`, `[`, `]`) are automatically removed from log folder paths, so logs will still be saved to `C:\ProgramData\IntuneLogs\Applications\innovaphone myApps\`.
> 
> **Note:** When using wildcards, the script uses PowerShell's `-like` operator for matching instead of exact matching (`-eq`). This feature works in all scripts (install, uninstall, and detection).

**`$applicationVersion` - Registry DisplayVersion (optional)**

Set `$applicationVersion` in `installExe.ps1`, `installMsi.ps1`, and `detectionWithVersionCheck.ps1` to the **exact `DisplayVersion`** from the registry when you want version-specific behavior. Leave empty (`""`) for name-only checks (default). Install scripts verify both `DisplayName` and `DisplayVersion` after setup and may **exit early** before install if both already match (see **`$applicationVersion` in the install scripts**). `uninstall.ps1` only uses `$applicationName` (and wildcards); post-uninstall validation checks that the matching display name is no longer in the uninstall registry.

**How to find the DisplayVersion:**

1. **Using Add/Remove Programs (appwiz.cpl):**
   - Open `appwiz.cpl` (see Method 1 above)
   - Right-click the column headers and enable "Version" column if not visible
   - **Write down the exact version** as it appears in the Version column
   - This matches the registry `DisplayVersion` exactly

2. **Using Registry Editor or PowerShell:**
   - Use the same methods as above to locate your application in the registry
   - Look for the `DisplayVersion` value in the same registry key as `DisplayName`
   - Copy the **exact** value (e.g., `"1.9.18"`, `"2.0.0"`, `"2024.1"`)

**Example:**
```powershell
# If registry shows:
# DisplayName: "Microsoft Visual Studio Code"
# DisplayVersion: "1.85.1"

$applicationName = "Microsoft Visual Studio Code"
$applicationVersion = "1.85.1"
```

#### 🤖 Behavior

* ✅ Verifies that the installer 📄 exists at `$installerPath`
* ✅ **Registry check before install** and **verification after install**—see **`$applicationVersion` in the install scripts**
* ✅ Launches the EXE installer with specified arguments
* ✅ Captures process ID and exit code
* ✅ Performs post-installation verification by checking registry (with retry logic)
* ✅ Writes logs via `Write-Log` when enabled (see **Logging & Diagnostics**)
* ✅ Exits with `0` on success (verified in registry or skipped as already present), `1` on error

#### 📁 Log Location

Log directory uses `$scriptName` in the script (same as `$applicationNameClean`: wildcards stripped for the folder name).

```text
C:\ProgramData\IntuneLogs\Applications\<scriptName>\install.log
```

---

### 📜 `installMsi.ps1` - MSI Installer Script

#### 🔧 Parameters (top of `installMsi.ps1`)

Same idea as `installExe.ps1`: **Configuration**, **UNC**, **Logging**, plus MSI-specific `$installerArguments`. **`$applicationVersion`** behaves the same as in **`$applicationVersion` in the install scripts** (EXE section above).

| Variable | Purpose |
| -------- | ------- |
| `$applicationName` | Registry `DisplayName` for verification (wildcards supported; see Configuration Guide). |
| `$applicationVersion` | Optional; skip-before-install + post-install rules—see **`$applicationVersion` in the install scripts**. |
| `$installerName` | Filename of the `.msi` next to the script (or on UNC). |
| `$installerArguments` | Arguments for `msiexec` **after** `/i` and the MSI path (e.g. `'/qn /norestart'`). Do **not** put `/i` or the `.msi` path here—the script adds them. |
| `$createShortcuts`, `$desktopShortcuts`, `$startMenuShortcuts` | Same shortcut behavior as `installExe.ps1`. |
| `$installerPathOverride`, `$useUncAuth`, `$uncCredential` | Optional UNC (same as EXE). |
| `$registrySearchPaths` | Where to look for the app after install (defaults cover 64- and 32-bit uninstall hives). |
| `$log`, `$logDebug`, `$logGet`, `$logRun`, `$enableLogFile` | Logging switches—see **Logging & Diagnostics**. |

**`$installerArguments` examples:** `'/qn'`, `'/qn /norestart'`, `'/qn /l*v "C:\path\msi.log"'`.

> `$installerPath` is UNC root + `$installerName` when `$installerPathOverride` is set; otherwise the script folder + `$installerName`.

#### 📋 Configuration examples

**Scenario A: Basic MSI, no shortcuts**

```powershell
$applicationName     = "Microsoft Visual Studio Code"
$applicationVersion  = "1.85.1"
$installerName       = "VSCodeUserSetup-x64-1.85.1.msi"
$installerArguments  = '/qn /norestart'
$createShortcuts     = $false
$desktopShortcuts    = @()
$startMenuShortcuts  = @()
```

**Scenario B: MSI with shortcuts** (installer does not create shortcuts in SYSTEM context)

```powershell
$applicationName     = "My Application"
$applicationVersion  = ""
$installerName       = "MyApp-2.1.0.msi"
$installerArguments  = '/qn /norestart'
$createShortcuts     = $true
$desktopShortcuts    = @(
    @{ Name = "My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
$startMenuShortcuts  = @(
    @{ Name = "MyApp\My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
```

**Scenario C: MSI with verbose logging** (for troubleshooting)

```powershell
$applicationName     = "My Application"
$applicationVersion  = ""
$installerName       = "MyApp-2.1.0.msi"
$installerArguments  = '/qn /norestart /l*v "C:\ProgramData\IntuneLogs\Applications\My Application\msi-install.log"'
$createShortcuts     = $false
$desktopShortcuts    = @()
$startMenuShortcuts  = @()
```

**Scenario D: MSI on UNC share** (Entra-joined devices)

```powershell
$applicationName     = "My Application"
$applicationVersion  = ""
$installerName       = "MyApp-2.1.0.msi"
$installerArguments  = '/qn /norestart'
$createShortcuts     = $false
$desktopShortcuts    = @()
$startMenuShortcuts  = @()

# UNC section
$installerPathOverride = "\\server01.domain.tld\software"
$useUncAuth           = $true
$uncCredential        = [PSCredential]::new("svc.intune-install@domain.tld", (ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force))
```

> **UNC credential:** Same `))` closing parentheses and PowerShell 7+ requirement as in the EXE **Scenario E** example above.

#### 📝 Configuration Guide

**`$installerName` - Installer File Name**

Set `$installerName` to the **exact filename** of your MSI installer file (including the `.msi` extension). This file must be included in the same folder as the script when packaging.

* ✅ **Correct:** `$installerName = "MyApplication-v2.1.0.msi"` (matches the actual filename)
* ✅ **Correct:** `$installerName = "setup.msi"` (if your installer is named `setup.msi`)
* ❌ **Incorrect:** `$installerName = "installer"` (missing file extension)
* ❌ **Incorrect:** `$installerName = "C:\Path\To\Installer.msi"` (should only be the filename, not the full path)

**`$applicationName` - Registry DisplayName**

The `$applicationName` variable must match the **exact `DisplayName`** value from the Windows registry after installation. This is used for:
- Post-installation verification
- Detection scripts
- Uninstall registry lookup

**How to find the DisplayName:**

1. **Method 1: Using Add/Remove Programs (appwiz.cpl)** ⭐ **Easiest Method**
   - Press `Win + R`, type `appwiz.cpl`, press Enter
   - Find your application in the list
   - **Write down the exact name** as it appears (including spaces, capitalization, and special characters)
   - If you need the version, look at the "Version" column (if visible) or right-click the column headers and enable "Version" column
   - This name matches the registry `DisplayName` exactly

2. **Method 2: Using Registry Editor (regedit.exe)**
   - Press `Win + R`, type `regedit`, press Enter
   - Navigate to: `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
   - **Also check:** `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
     - Some 32-bit applications register in the WOW6432Node path on 64-bit systems
   - Browse through the subkeys (GUIDs or product codes)
   - Look for the `DisplayName` value that matches your application
   - Copy the **exact** value (case-sensitive)

3. **Method 3: Using PowerShell (on a test machine with the app installed)**
   ```powershell
   # Check both registry paths
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*YourAppName*" } | 
       Select-Object DisplayName, DisplayVersion
   
   Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
       Where-Object { $_.DisplayName -like "*YourAppName*" } | 
       Select-Object DisplayName, DisplayVersion
   ```

**Important:** The `DisplayName` must match **exactly** (case-sensitive, including spaces and special characters).

> [!TIP]
> **Wildcard Support:** If your application's `DisplayName` changes with version numbers (e.g., "innovaphone myApps 1510655"), you can use wildcard matching by adding a `*` to the end of `$applicationName`:
> 
> ```powershell
> $applicationName = "innovaphone myApps*"
> ```
> 
> This will match any `DisplayName` that starts with "innovaphone myApps" (e.g., "innovaphone myApps 1510655", "innovaphone myApps 1510656", etc.). The wildcard characters (`*`, `?`, `[`, `]`) are automatically removed from log folder paths, so logs will still be saved to `C:\ProgramData\IntuneLogs\Applications\innovaphone myApps\`.
> 
> **Note:** When using wildcards, the script uses PowerShell's `-like` operator for matching instead of exact matching (`-eq`). This feature works in all scripts (install, uninstall, and detection).

**`$applicationVersion` - Registry DisplayVersion (optional)**

Set `$applicationVersion` in `installExe.ps1`, `installMsi.ps1`, and `detectionWithVersionCheck.ps1` to the **exact `DisplayVersion`** from the registry when you want version-specific behavior. Leave empty (`""`) for name-only checks (default). Install scripts verify both `DisplayName` and `DisplayVersion` after setup and may **exit early** before install if both already match (see **`$applicationVersion` in the install scripts**). `uninstall.ps1` only uses `$applicationName` (and wildcards); post-uninstall validation checks that the matching display name is no longer in the uninstall registry.

**How to find the DisplayVersion:**

1. **Using Add/Remove Programs (appwiz.cpl):**
   - Open `appwiz.cpl` (see Method 1 above)
   - Right-click the column headers and enable "Version" column if not visible
   - **Write down the exact version** as it appears in the Version column
   - This matches the registry `DisplayVersion` exactly

2. **Using Registry Editor or PowerShell:**
   - Use the same methods as above to locate your application in the registry
   - Look for the `DisplayVersion` value in the same registry key as `DisplayName`
   - Copy the **exact** value (e.g., `"1.9.18"`, `"2.0.0"`, `"2024.1"`)

**Example:**
```powershell
# If registry shows:
# DisplayName: "Microsoft Visual Studio Code"
# DisplayVersion: "1.85.1"

$applicationName = "Microsoft Visual Studio Code"
$applicationVersion = "1.85.1"
```

**Shortcut Creation (Optional) – `installExe.ps1` & `installMsi.ps1`**

Mitigates installers that do not create shortcuts when run in SYSTEM context. Configure separate shortcut lists for **Public Desktop** and **All Users Start Menu** (e.g. more Start Menu shortcuts than desktop).

* Set `$createShortcuts = $true` to enable
* `$desktopShortcuts` – shortcuts on Public Desktop (visible to all users)
* `$startMenuShortcuts` – shortcuts in All Users Start Menu

Each shortcut is a hashtable: `Name` (display name), `TargetPath` (exe path; supports `$env:Variable`), and optionally `Arguments` and `WorkingDirectory`. Use `"Folder\ShortcutName"` in `Name` to create subfolders (e.g. `"MyApp\Shortcut1"` creates `Programs\MyApp\Shortcut1.lnk`; the folder is created if it does not exist). The script checks if each shortcut exists; missing ones are created, existing ones are left unchanged.

```powershell
$createShortcuts = $true
$desktopShortcuts = @(
    @{ Name = "My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" }
)
$startMenuShortcuts = @(
    @{ Name = "MyApp\My Application"; TargetPath = "$env:ProgramFiles\MyApp\myapp.exe" },
    @{ Name = "MyApp\My App Help"; TargetPath = "$env:ProgramFiles\MyApp\help.exe"; WorkingDirectory = "$env:ProgramFiles\MyApp" }
)
```

#### 🤖 Behavior

* ✅ Verifies that the MSI installer 📄 exists at `$installerPath`
* ✅ **Registry check before install** and **verification after install** (same rules as EXE)—see **`$applicationVersion` in the install scripts**
* ✅ Constructs MSI command: `msiexec.exe /i "<path>" $installerArguments`
* ✅ Launches the MSI installation via `msiexec.exe`
* ✅ Captures process ID and exit code
* ✅ Performs post-installation verification by checking registry (with retry logic)
* ✅ Handles MSI exit codes (0 = success, 3010 / 1641 = reboot-related success)
* ✅ Writes logs via `Write-Log` when enabled (see **Logging & Diagnostics**)
* ✅ Exits with `0` on success (verified in registry or skipped as already present), `1` on error

#### 📁 Log Location

Same as EXE: folder name is `$scriptName` / `$applicationNameClean` in the script.

```text
C:\ProgramData\IntuneLogs\Applications\<scriptName>\install.log
```

---

## 🗑️ `uninstall.ps1` Overview 📜

### 🎯 Purpose

Uninstalls the application using either:

* ✅ A **packaged EXE/MSI** included with the Win32 app (recommended), or
* ✅ The **registry UninstallString** entry

Includes automatic post-uninstall validation and fallback mechanisms.

### 🔧 Parameters (top of `uninstall.ps1`)

There is **no** `$applicationVersion` in uninstall: validation only checks that the **DisplayName** (with the same wildcard rules as install) no longer appears under `$registrySearchPaths`. File retries, wildcard handling, and logging use the defaults in the script unless you change them.

| Variable | Purpose |
| -------- | ------- |
| `$applicationName` | Registry `DisplayName` for lookup and post-uninstall check. Supports wildcards (`*`, `?`, `[`, `]`). |
| `$usePackagedUninstaller` | `$true` = use packaged EXE/MSI; `$false` = use registry `UninstallString`/`ModifyPath`. |
| `$installerName` | Filename of packaged uninstaller (used only when `$usePackagedUninstaller = $true`). |
| `$uninstallerArgumentsExe` | Arguments for non-MSI uninstallers (e.g. `/uninstall /silent`). |
| `$uninstallerArgumentsMsi` | Arguments for MSI uninstall (e.g. `/qn`). |
| `$registrySearchPaths` | Registry paths for lookup and validation. Default covers 64-bit and 32-bit apps. |
| `$log`, `$logDebug`, `$logGet`, `$logRun`, `$enableLogFile` | Logging switches. See Logging section. |

**UNC Path & Authentication** (optional – when packaged uninstaller is on UNC): `$installerPathOverride`, `$useUncAuth`, `$uncCredential` (PSCredential).

> `$installerPath` is computed: if `$installerPathOverride` is set → UNC root + `$installerName`; else → script folder + `$installerName`.

#### 📋 Configuration examples

**Scenario A: Packaged EXE uninstaller** (same file as install, or dedicated uninstaller)

```powershell
$applicationName         = "My Application"
$usePackagedUninstaller  = $true
$installerName           = "MyAppSetup.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'
```

**Scenario B: Packaged MSI uninstaller** (same MSI used for install and uninstall via msiexec /x)

```powershell
$applicationName         = "My Application"
$usePackagedUninstaller  = $true
$installerName           = "MyApp-2.1.0.msi"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'
```

**Scenario C: Registry-based uninstall** (script finds UninstallString from registry; no packaged uninstaller)

```powershell
$applicationName         = "My Application"
$usePackagedUninstaller  = $false
$installerName           = "setup.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'
```

**Scenario D: Registry-based with wildcard DisplayName**

```powershell
$applicationName         = "innovaphone myApps*"
$usePackagedUninstaller  = $false
$installerName           = "setup.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'
```

**Scenario E: Packaged uninstaller on UNC share**

```powershell
$applicationName         = "My Application"
$usePackagedUninstaller  = $true
$installerName           = "uninstall.exe"
$uninstallerArgumentsExe = '/uninstall /silent'
$uninstallerArgumentsMsi = '/qn'

# UNC section
$installerPathOverride = "\\server01.domain.tld\software"
$useUncAuth           = $true
$uncCredential        = [PSCredential]::new("svc.intune-install@domain.tld", (ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force))
```

> **UNC credential:** Line must end with `))`; use PowerShell 7+ for `-AsPlainText -Force` (see **Install Issues** troubleshooting).

### ✅ Mode A — Packaged Uninstaller (`$usePackagedUninstaller = $true`)

* 🔍 Validates that the packaged uninstaller 📄 exists
* 🧠 Detects `.exe` or `.msi` automatically
* ▶️ Runs:
  * MSI → `msiexec.exe /x "<path>" $uninstallerArgumentsMsi`
  * EXE → `"<path>" $uninstallerArgumentsExe`
* 🧾 Logs path, arguments, PID, and exit code
* ✅ Performs post-uninstall validation (checks registry with retries)
* 🚪 Exits with the process exit code (0 = success, verified in registry)

### ✅ Mode B — Registry-Based Uninstall (`$usePackagedUninstaller = $false`)

* 🔍 Searches uninstall registry keys for `DisplayName` matching `$applicationName` (exact match or wildcard match if `*` is present)
* 📖 Reads `UninstallString` and `ModifyPath` from registry. Prefers MSI when both exist; if `UninstallString` is non-MSI and `ModifyPath` is MSI, uses `ModifyPath` (and corrects `/I` → `/X` for msiexec)
* 🧠 Automatically detects MSI vs EXE uninstallers
* 🧠 If MSI → ensures `/qn` or `$uninstallerArgumentsMsi` is present
* 🧠 If non-MSI → appends `$uninstallerArgumentsExe` (avoiding duplicates)
* ▶️ Executes the uninstaller via `Start-Process`
* ✅ Performs post-uninstall validation (checks registry with retries). On success the script logs **`Missing from reg.`**
* 🔄 Fallback: if validation fails, searches for another `UninstallString` for the same app and retries once
* 🚪 Exits with `0` on success (verified removal), `1` on error

### 📁 Log Location

```text
C:\ProgramData\IntuneLogs\Applications\<scriptName>\uninstall.log
```

---

## 🔍 Detection Scripts 📜

These 📜 scripts are used **only** for Intune detection rules and are **not** part of the `.intunewin` package.

---

### ✅ `detectionWithVersionCheck.ps1` 📜

#### 🎯 Purpose

Detects whether a specific **DisplayName + DisplayVersion** combination is present in the uninstall registry keys.

#### 🔧 Parameters (top of `detectionWithVersionCheck.ps1`)

Set the placeholders and optional `$registrySearchPaths`. Logging switches match the other scripts.

| Variable | Purpose |
| -------- | ------- |
| `$applicationName` | Registry `DisplayName` (supports wildcards). |
| `$applicationVersion` | Registry `DisplayVersion` – must match exactly. |
| `$registrySearchPaths` | Registry paths to search. Default covers 64-bit and 32-bit apps. |
| `$log`, `$logDebug`, `$logGet`, `$logRun`, `$enableLogFile` | Logging switches. See Logging section. |

#### 📋 Configuration examples

**Scenario A: Exact DisplayName and DisplayVersion** (e.g. version-specific upgrade detection)

```powershell
$applicationName    = "Microsoft Visual Studio Code"
$applicationVersion = "1.85.1"
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

**Scenario B: Wildcard DisplayName, exact version** (e.g. innovaphone myApps 1510655)

```powershell
$applicationName    = "innovaphone myApps*"
$applicationVersion = "1510655"
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

> 📝 **Note:** See the **Configuration Guide** in the Installation Scripts section above for detailed instructions on how to find the exact `DisplayName` and `DisplayVersion` values from the Windows registry.

#### 🤖 Logic

* Scans uninstall subkeys under each path in `$registrySearchPaths`
* Matches `DisplayName` to `$applicationName` (wildcard `-like` when the name contains `*`, `?`, or `[` / `]`, otherwise `-eq`) and `DisplayVersion` to `$applicationVersion` (exact)
* **Installed:** `Complete-Script -exitCode 0`
* **Not installed:** `Complete-Script -exitCode 1`
* Extra registry scan detail is emitted only when `$logDebug = $true`

#### 📌 Use When

* You want **version-specific** detection for upgrades
* You require that **only version X.Y.Z** counts as installed

---

### ✅ `detectionWithoutVersionCheck.ps1` 📜

#### 🎯 Purpose

Detects whether the application is installed based only on `DisplayName`.

#### 🔧 Parameters (top of `detectionWithoutVersionCheck.ps1`)

Only `$applicationName` and optionally `$registrySearchPaths` (and logging) need tuning for most apps.

| Variable | Purpose |
| -------- | ------- |
| `$applicationName` | Registry `DisplayName` (supports wildcards). |
| `$registrySearchPaths` | Registry paths to search. Default covers 64-bit and 32-bit apps. |
| `$log`, `$logDebug`, `$logGet`, `$logRun`, `$enableLogFile` | Logging switches. See Logging section. |

#### 📋 Configuration examples

**Scenario A: Exact DisplayName** (any version counts as installed)

```powershell
$applicationName = "Microsoft Visual Studio Code"
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

**Scenario B: Wildcard DisplayName** (e.g. app that changes name with version)

```powershell
$applicationName = "innovaphone myApps*"
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

> 📝 **Note:** See the **Configuration Guide** in the Installation Scripts section above for detailed instructions on how to find the exact `DisplayName` value from the Windows registry.

#### 🤖 Logic

* Scans uninstall subkeys under each path in `$registrySearchPaths`
* Matches `DisplayName` to `$applicationName` (wildcard `-like` when the name contains wildcard characters, otherwise `-eq`); any `DisplayVersion` is ignored for the decision
* **Installed:** exit code `0`
* **Not installed:** exit code `1`
* Per-hive detail is **Debug** only when `$logDebug = $true`

#### 📌 Use When

* Any version of the app is acceptable
* The app auto-updates
* You only care about presence, not version

---

## 📦 Packaging as a Win32 App

### 🛠 Required Tool

Use the official **Microsoft-Win32-Content-Prep-Tool** to create `.intunewin` packages: 
🔗 [https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)

### 📁 Example Source Layout

**For EXE installer:**
```text
📁 C:\IntuneApps\<ApplicationName>
│
├─📜 install.ps1          (renamed from installExe.ps1)
├─📜 uninstall.ps1
└─📄 <YourInstaller>.exe
```

**For MSI installer:**
```text
📁 C:\IntuneApps\<ApplicationName>
│
├─📜 install.ps1          (renamed from installMsi.ps1)
├─📜 uninstall.ps1
└─📄 <YourInstaller>.msi
```

### 🚀 Run the Packaging Tool

From a PowerShell or CMD session:

```text
IntuneWinAppUtil.exe
```

Then answer the prompts:

```text
Please specify the source folder: C:\IntuneApps\<ApplicationName>
Please specify the setup file:   install.ps1
Please specify the output folder: C:\IntuneApps\Output
Do you want to specify catalog folder (Y/N)? N
```

✅ Output: a single `.intunewin` 📄 file in `C:\IntuneApps\Output\`

---

## 🏢 Upload & Configure in Microsoft Intune

### 1️⃣ Add the Win32 App

1. Open **Intune Admin Center** 🌐
2. Go to **📂 Apps → Windows → Add**
3. Choose **Windows app (Win32)**
4. Upload the generated `.intunewin` 📄

Fill out Name, Description, Publisher, etc.

---

### 2️⃣ Program Settings ⚙️

**Install command** 🟢

```text
%WINDIR%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass .\install.ps1
```

**Uninstall command** 🔴

```text
%WINDIR%\sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1
```

* Install behavior: `System`
* Device restart behavior: `Determine behavior based on return codes`
* Return codes: See [Return codes and Intune handling](#return-codes-and-intune-handling) below.

---

### 3️⃣ Return Codes and Intune Handling

Configure these return codes in the Win32 app: **Properties → Return codes** (add or edit as needed).

| Return code | Code type in Intune | Meaning | How Intune handles it |
|-------------|---------------------|---------|------------------------|
| `0` | Success | Installation completed successfully (verified in registry). | App marked as installed. No restart. |
| `1` | Failed | Installation failed, installer error, or registry verification failed. | App marked as failed. No restart. |
| `3010` | Soft reboot | Success, but a restart is required to complete installation (common MSI code). | App marked as installed. User notified; other apps can install before restart. |
| `1641` | Hard reboot | Success; installer initiated restart (e.g. EXE/Setup.exe). | App marked as installed. Restart required; other apps wait. User notified. |

**Recommended configuration in Intune** (Program → Return codes):

| Code | Type |
|------|------|
| 0 | Success |
| 1 | Failed |
| 3010 | Soft reboot |
| 1641 | Hard reboot |

#### Device restart behavior options

Set in **Properties → Program → Device restart behavior**:

| Option | Effect |
|--------|--------|
| **Determine behavior based on return codes** | Use the return code types above. Soft reboot = notify user; Hard reboot = trigger restart. Best for this framework. |
| **App install may force a device restart** | Similar, but Hard reboot gives ~120 min grace before restart. |
| **Intune will force a mandatory device restart** | Any success (including 0) triggers an immediate restart. |
| **No specific action** | Suppresses restarts (MSI /qn or similar). Not recommended for apps that need reboot. |

#### How the scripts map exit codes

- **installExe.ps1** and **installMsi.ps1** pass through the installer exit code when verification succeeds (including 0, 3010, 1641).
- On failure or failed verification, they exit with `1`.
- Intune receives the script exit code and applies the matching return code type.

---

### 4️⃣ Detection Rules 🔍

> 🧠 Remember: Detection 📜 scripts are **not** inside the `.intunewin` – you upload them separately as `detection.ps1`.

#### Option A – Version-Based Detection

Use `detectionWithVersionCheck.ps1` 📜 (rename to `detection.ps1` before uploading)

* Rules format: **Use a custom detection script**
* Upload: `detection.ps1` (renamed from `detectionWithVersionCheck.ps1`)
* Exit codes:
  * `0` → application with correct version is installed
  * `1` → not installed / wrong version

#### Option B – Presence-Only Detection

Use `detectionWithoutVersionCheck.ps1` 📜 (rename to `detection.ps1` before uploading)

* Rules format: **Use a custom detection script**
* Upload: `detection.ps1` (renamed from `detectionWithoutVersionCheck.ps1`)
* Exit codes:
  * `0` → application installed
  * `1` → application not installed

---

## 🧪 Test Scripts Manually

Before rolling out via Intune, you should test each 📜 script on a **test device**.

### ▶️ Quick Local Test (Current User Context)

From an elevated PowerShell prompt:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
```

This verifies basic logic, paths, and silent install parameters.

### 🧪 Recommended Test – Run as SYSTEM with PsExec

Intune runs Win32 app scripts in the **SYSTEM** context. To realistically simulate this on a test device:

1. Download the **PsTools** suite (which includes `PsExec.exe`) from Microsoft Learn:
   🔗 [https://learn.microsoft.com/en-us/sysinternals/downloads/pstools](https://learn.microsoft.com/en-us/sysinternals/downloads/pstools)

2. Extract the 📦 ZIP and open an elevated **Command Prompt** in the folder containing `PsExec.exe`.

3. Launch a SYSTEM-level interactive PowerShell session:

   ```PowerShell
   .\PsExec.exe -i -s powershell.exe
   ```

   * `-i` → interactive session (visible on your desktop)
   * `-s` → runs under the **Local System** account

4. In this new SYSTEM PowerShell window, navigate to your app 📁 folder and run:

   ```powershell
   .\install.ps1
   .\detection.ps1
   .\uninstall.ps1
   ```

This lets you confirm that the scripts behave correctly when executed exactly like Intune would (SYSTEM account).

---

## 🪵 Logging & Diagnostics

Each script defines **`Write-Log`** and writes optional **UTF-8** log files under:

`$env:ProgramData\IntuneLogs\Applications\$scriptName`

`$scriptName` is `$applicationNameClean` (wildcard characters stripped from `$applicationName` for the folder name).

| After rename | Log file |
| ------------ | -------- |
| `install.ps1` | `install.log` |
| `uninstall.ps1` | `uninstall.log` |
| `detection.ps1` | `detection.log` |

To collect that folder with Intune **Collect diagnostics**, you can use: [**Diagnostics - Custom Log File Directory**](https://github.com/Barg0/Intune-Platform-Scripts/tree/main/Diagnostics%20-%20Custom%20Log%20File%20Directory).

### 📝 Log switches (same names in each script)

```powershell
$log              = $true
$logDebug         = $false
$logGet           = $true
$logRun           = $true
$enableLogFile    = $true
```

`$log` disables all logging. `$logDebug`, `$logGet`, and `$logRun` filter message categories inside `Write-Log`. Set `$enableLogFile = $false` to keep console output only.


## 🌟 Wildcard Support Feature

### 🎯 Purpose

Some applications (like Citrix Workspace or innovaphone MyApps) change their `DisplayName` in the registry according to version numbers. For example:
- `"innovaphone myApps 1510655"`
- `"innovaphone myApps 1510656"`
- `"Citrix Workspace 2402.1.0.12"`

Instead of updating your scripts every time a new version is released, you can use wildcard matching.

### 📝 How to Use

Simply add a wildcard character (`*`) to your `$applicationName` variable:

```powershell
$applicationName = "innovaphone myApps*"
```

This will match any `DisplayName` that starts with "innovaphone myApps", regardless of what comes after.

### ✅ Supported Wildcard Characters

* `*` - Matches zero or more characters
* `?` - Matches exactly one character
* `[abc]` - Matches any character in the brackets
* `[a-z]` - Matches any character in the range

### 📁 Log Path Behavior

When wildcard characters are detected in `$applicationName`, they are automatically removed from log folder paths:

* **With wildcard:** `$applicationName = "innovaphone myApps*"`
* **Log folder:** `C:\ProgramData\IntuneLogs\Applications\innovaphone myApps\`

This ensures clean folder names without special characters.

### 🔍 Where It Works

Wildcard support is available in **all scripts**:
* ✅ `installExe.ps1` / `installMsi.ps1` - Skip-before-install when version is set, post-install verification, name-only path when version is empty (see **`$applicationVersion` in the install scripts**)
* ✅ `uninstall.ps1` - Registry lookup and validation
* ✅ `detectionWithVersionCheck.ps1` - DisplayName matching (version still requires exact match)
* ✅ `detectionWithoutVersionCheck.ps1` - DisplayName matching

### 📌 Important Notes

1. **Version matching:** In `detectionWithVersionCheck.ps1`, the `DisplayName` uses wildcard matching, but `DisplayVersion` still requires an exact match.

2. **Backward compatibility:** If your `$applicationName` doesn't contain wildcard characters, the scripts will use exact matching (`-eq`) as before. No changes needed for existing deployments.

3. **Example usage:**
   ```powershell
   # Exact match (existing behavior)
   $applicationName = "Microsoft Visual Studio Code"
   
   # Wildcard match (new feature)
   $applicationName = "innovaphone myApps*"
   $applicationName = "Citrix Workspace*"
   ```

---

## 🛠 Troubleshooting Tips

### ⚠️ Install Issues

* Double-check installer arguments (`/quiet`, `/qn`, `/silent`)
* Verify the installer file name matches `$installerName` exactly
* **`[PSCredential]::new` parse error:** ensure the line ends with **`))`** (one `)` closes `ConvertTo-SecureString`, one closes `::new`). Use **PowerShell 7+** for `ConvertTo-SecureString -AsPlainText -Force`.
* Turn on debug logging: set `$logDebug = $true` in the configuration section
* Run the installer manually with the same arguments to see vendor errors
* Check the registry manually to confirm the `DisplayName` matches `$applicationName` exactly

### ⚠️ Uninstall Issues

* Verify whether `$usePackagedUninstaller` is set as intended
* If using registry mode, confirm the `DisplayName` exactly matches `$applicationName`
* Inspect the raw `UninstallString` on a test device and try it manually
* Check if the uninstaller requires different arguments than configured
* Review logs for fallback uninstall attempts

### ⚠️ Detection Issues

* Run the detection 📜 scripts manually on a test device
* Confirm `DisplayName` / `DisplayVersion` in:
  * `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
  * `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
* Ensure the `DisplayName` matches exactly (case-sensitive) or use wildcard matching if the name changes with versions
* For version detection, verify the `DisplayVersion` format matches exactly
* If using wildcards, test the pattern manually: `"DisplayName" -like "YourPattern*"`

### ⚠️ Logging Issues

* Ensure the log directory path is accessible: `C:\ProgramData\IntuneLogs\Applications\<scriptName>\` (same folder name the script derives from `$applicationName`)
* Check file permissions - scripts run as SYSTEM, so SYSTEM must have write access
* If logs aren't appearing, set `$enableLogFile = $true` and verify `$log = $true`
* Enable debug logging by setting `$logDebug = $true` for more detailed information

---
