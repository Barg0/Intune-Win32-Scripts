# 🚀 Win32 App Deployment Framework for Microsoft Intune

This repository provides a **reusable, configurable, and standardized PowerShell deployment framework** for packaging, installing, uninstalling, and detecting Win32 applications in **Microsoft Intune**. 🎯

✅ Supports **EXE & MSI installers**
✅ Unified **logging** with multiple log levels
✅ Registry **or** packaged uninstaller support
✅ Post-installation verification via registry detection
✅ Comprehensive error handling and retry logic

You can deploy **any Win32 application** by modifying just a few variables at the top of each 📜 script.

---

## ⚠️ **IMPORTANT: File Renaming Required** ⚠️

> [!WARNING]
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
> 4. Configure the variables in `install.ps1` and `detection.ps1` (application name, installer name, arguments, etc.)
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

### 📜 `installExe.ps1` - EXE Installer Script

#### 🔧 Configuration (top of script)

```powershell
$applicationName  = "__REGISTRY_DISPLAY_NAME__"

$installerName        = "setup.exe"
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# EXE installer arguments
$installerArgumentsExe = '/silent'

# Registry paths to search for the installed application
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

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

**`$applicationVersion` - Registry DisplayVersion (for detection scripts with version check)**

If using `detectionWithVersionCheck.ps1`, you also need to set `$applicationVersion` to match the **exact `DisplayVersion`** value from the registry.

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
* ✅ Launches the EXE installer with specified arguments
* ✅ Captures process ID and exit code
* ✅ Performs post-installation verification by checking registry (with retry logic)
* ✅ Logs all actions (arguments, PID, exit code, verification results)
* ✅ Exits with `0` on success (verified in registry), `1` on error

#### 📁 Log Location

```text
C:\ProgramData\IntuneLogs\Applications\<applicationName>\install.log
```

---

### 📜 `installMsi.ps1` - MSI Installer Script

#### 🔧 Configuration (top of script)

```powershell
$applicationName  = "__REGISTRY_DISPLAY_NAME__"

$installerName        = "setup.msi"
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# MSI installer arguments
# The /i switch and installer path are automatically prepended
# Add all additional MSI arguments here (e.g., /qn, /norestart, TRANSFORMS, PROPERTIES, etc.)
$installerArguments = "/qn /norestart"

# Registry paths to search for the installed application
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

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

**`$applicationVersion` - Registry DisplayVersion (for detection scripts with version check)**

If using `detectionWithVersionCheck.ps1`, you also need to set `$applicationVersion` to match the **exact `DisplayVersion`** value from the registry.

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

* ✅ Verifies that the MSI installer 📄 exists at `$installerPath`
* ✅ Constructs MSI command: `msiexec.exe /i "<path>" $installerArguments`
* ✅ Launches the MSI installation via `msiexec.exe`
* ✅ Captures process ID and exit code
* ✅ Performs post-installation verification by checking registry (with retry logic)
* ✅ Handles MSI exit codes (0 = success, 3010 = success with reboot required)
* ✅ Logs all actions (arguments, PID, exit code, verification results)
* ✅ Exits with `0` on success (verified in registry), `1` on error

#### 📁 Log Location

```text
C:\ProgramData\IntuneLogs\Applications\<applicationName>\install.log
```

---

## 🗑️ `uninstall.ps1` Overview 📜

### 🎯 Purpose

Uninstalls the application using either:

* ✅ A **packaged EXE/MSI** included with the Win32 app (recommended), or
* ✅ The **registry UninstallString** entry

Includes automatic post-uninstall validation and fallback mechanisms.

### 🔧 Configuration (top of script)

```powershell
$applicationName = "__REGISTRY_DISPLAY_NAME__"

# Mode selection
$usePackagedUninstaller = $false   # $true = packaged uninstaller, $false = registry-based

# Packaged uninstaller configuration (used only when $usePackagedUninstaller = $true)
$installerName = "setup.exe"           # or .msi
$installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# Uninstaller arguments
$uninstallerArgumentsExe = "/uninstall /silent"               # For non-MSI uninstallers
$uninstallerArgumentsMsi = "/qn"                              # For MSI uninstall (msiexec /x ...)

# Registry locations to search for uninstall entries
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

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

* 🔍 Searches uninstall registry keys for `DisplayName -eq $applicationName`
* 📖 Reads `UninstallString` from registry
* 🧠 Automatically detects MSI vs EXE uninstallers
* 🧠 If MSI → ensures `/qn` or `$uninstallerArgumentsMsi` is present
* 🧠 If non-MSI → appends `$uninstallerArgumentsExe` (avoiding duplicates)
* ▶️ Executes the uninstaller via `Start-Process`
* ✅ Performs post-uninstall validation (checks registry with retries)
* 🔄 Includes fallback mechanism if first uninstall attempt fails validation
* 🚪 Exits with `0` on success (verified removal), `1` on error

### 📁 Log Location

```text
C:\ProgramData\IntuneLogs\Applications\<applicationName>\uninstall.log
```

---

## 🔍 Detection Scripts 📜

These 📜 scripts are used **only** for Intune detection rules and are **not** part of the `.intunewin` package.

---

### ✅ `detectionWithVersionCheck.ps1` 📜

#### 🎯 Purpose

Detects whether a specific **DisplayName + DisplayVersion** combination is present in the uninstall registry keys.

#### 🔧 Configuration

```powershell
$applicationName    = "__REGISTRY_DISPLAY_NAME__"
$applicationVersion = "__REGISTRY_DISPLAY_VERSION__"   # e.g. "1.9.18"

$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

> 📝 **Note:** See the **Configuration Guide** in the Installation Scripts section above for detailed instructions on how to find the exact `DisplayName` and `DisplayVersion` values from the Windows registry.

#### 🤖 Logic

* Loops over all 📁 subkeys under each `$registrySearchPaths` entry
* Reads `DisplayName` and `DisplayVersion` for each key
* When both match:
  * ✅ Logs a success entry
  * ✅ Calls `Stop-Script -ExitCode 0`
* If no match is found:
  * ❌ Logs error
  * ❌ Calls `Stop-Script -ExitCode 1`

#### 📌 Use When

* You want **version-specific** detection for upgrades
* You require that **only version X.Y.Z** counts as installed

---

### ✅ `detectionWithoutVersionCheck.ps1` 📜

#### 🎯 Purpose

Detects whether the application is installed based only on `DisplayName`.

#### 🔧 Configuration

```powershell
$applicationName = "__REGISTRY_DISPLAY_NAME__"

$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

> 📝 **Note:** See the **Configuration Guide** in the Installation Scripts section above for detailed instructions on how to find the exact `DisplayName` value from the Windows registry.

#### 🤖 Logic

* Loops over uninstall registry keys
* Reads `DisplayName`
* When `DisplayName -eq $applicationName`:
  * ✅ Logs success
  * ✅ Exits with `0`
* Otherwise:
  * ❌ Logs error
  * ❌ Exits with `1`

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
* Device restart behavior: as required (often `No specific action`)

---

### 3️⃣ Detection Rules 🔍

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

All scripts share the same logging behavior and target the same 📁 log directory.

### 📄 Script Log Files

> [!TIP]
> The **📄 Log files** for all scripts are saved at:
> `C:\ProgramData\IntuneLogs\Applications\$applicationName\`
>
> ```
> C:  
> ├─📁 ProgramData
> │  └─📁 IntuneLogs
> │     └─📁 Applications
> │        └─📁 $applicationName
> │           ├─📄 detection.log
> │           ├─📄 install.log
> │           └─📄 uninstall.log
> ```
> To enable log collection from this custom directory using the **Collect diagnostics** feature in Intune, deploy the following platform script:
>
> [**📜 Diagnostics - Custom Log File Directory**](https://github.com/Barg0/Intune-Platform-Scripts/tree/main/Diagnostics%20-%20Custom%20Log%20File%20Directory)

### 📁 Script Logs (per app)

* `install.ps1`   → `install.log`
* `uninstall.ps1` → `uninstall.log`
* `detection.ps1` → `detection.log`

### 🏷️ Log Tags

All scripts use a unified logging system with the following tags:

* `[Start  ]` - Script initialization
* `[Get    ]` - Registry queries and file system checks
* `[Run    ]` - Process execution (installer/uninstaller launches)
* `[Info   ]` - General information messages
* `[Success]` - Successful operations
* `[Error  ]` - Errors and failures
* `[Debug  ]` - Detailed debugging information (controlled by `$logDebug`)
* `[End    ]` - Script completion

### 📝 Log Configuration

Each script includes logging configuration variables at the top:

```powershell
$log           = $true    # Master switch for all logging
$logDebug      = $false   # Set to $true to show DEBUG logs
$logGet        = $true    # Enable/disable all [Get] logs (registry searches)
$logRun        = $true    # Enable/disable all [Run] logs (process execution)
$enableLogFile = $true    # Enable/disable file logging
```

### 📋 Log Examples

> **Note:** All log examples show the exact format with correct padding. Tags are padded to 7 characters: `Start` → `Start  `, `Get` → `Get    `, `Run` → `Run    `, `Info` → `Info   `, `Success` → `Success` (no padding), `Error` → `Error  `, `Debug` → `Debug  `, `End` → `End    `.

---

## 📦 Installation Script Log Examples

### Example 1: Successful EXE Installation (First Attempt)

```
2026-01-25 10:15:23 [  Start   ] ======== Script Started ========
2026-01-25 10:15:23 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:15:23 [  Debug   ] Script configuration - InstallerName: 'setup.exe'
2026-01-25 10:15:23 [  Debug   ] Script configuration - InstallerPath: 'C:\Program Files\IntuneApps\MyApp\setup.exe'
2026-01-25 10:15:23 [  Debug   ] Script configuration - LogFile: 'C:\ProgramData\IntuneLogs\Applications\My Application\install.log'
2026-01-25 10:15:23 [  Get     ] Validating installer path...
2026-01-25 10:15:23 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 10:15:23 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:15:23 [  Debug   ] Launching process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' with arguments: /silent
2026-01-25 10:15:23 [  Debug   ] Installer process ID: 12345
2026-01-25 10:15:28 [  Info    ] Installer process has completed. Verifying installation via registry detection...
2026-01-25 10:15:28 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:15:28 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:15:28 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:15:28 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:15:29 [  Success ] Match found for application: 'My Application'
2026-01-25 10:15:29 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:15:29 [  Info    ] Script execution time: 00:00:06.45
2026-01-25 10:15:29 [  Info    ] Exit Code: 0
2026-01-25 10:15:29 [  End     ] ======== Script Completed ========
```

### Example 2: Successful EXE Installation (With Retry)

```
2026-01-25 10:20:15 [  Start   ] ======== Script Started ========
2026-01-25 10:20:15 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:20:15 [  Get     ] Validating installer path...
2026-01-25 10:20:15 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 10:20:15 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:20:15 [  Debug   ] Launching process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' with arguments: /silent
2026-01-25 10:20:15 [  Debug   ] Installer process ID: 12350
2026-01-25 10:20:20 [  Info    ] Installer process has completed. Verifying installation via registry detection...
2026-01-25 10:20:20 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:20:20 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:20:20 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:20:20 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:20:21 [  Info    ] Retry attempt 2 of 3 after 5 seconds...
2026-01-25 10:20:26 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:20:26 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:20:26 [  Success ] Match found for application: 'My Application'
2026-01-25 10:20:26 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:20:26 [  Info    ] Script execution time: 00:00:11.23
2026-01-25 10:20:26 [  Info    ] Exit Code: 0
2026-01-25 10:20:26 [  End     ] ======== Script Completed ========
```

### Example 3: Successful MSI Installation (First Attempt)

```
2026-01-25 10:25:10 [  Start   ] ======== Script Started ========
2026-01-25 10:25:10 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:25:10 [  Get     ] Validating installer path...
2026-01-25 10:25:10 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 10:25:10 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:25:10 [  Debug   ] Launching MSI installation via msiexec.exe with arguments: /i "C:\Program Files\IntuneApps\MyApp\setup.msi" /qn /norestart
2026-01-25 10:25:10 [  Debug   ] MSI installation process ID: 12355
2026-01-25 10:25:10 [  Info    ] MSI installation exit code: 0
2026-01-25 10:25:10 [  Success ] MSI installation completed successfully.
2026-01-25 10:25:10 [  Info    ] MSI installer process has completed. Verifying installation via registry detection...
2026-01-25 10:25:10 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:25:10 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:25:10 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:25:11 [  Success ] Match found for application: 'My Application'
2026-01-25 10:25:11 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:25:11 [  Info    ] Script execution time: 00:00:01.45
2026-01-25 10:25:11 [  Info    ] Exit Code: 0
2026-01-25 10:25:11 [  End     ] ======== Script Completed ========
```

### Example 4: Successful MSI Installation (With Retry)

```
2026-01-25 10:30:15 [  Start   ] ======== Script Started ========
2026-01-25 10:30:15 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:30:15 [  Get     ] Validating installer path...
2026-01-25 10:30:15 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 10:30:15 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:30:15 [  Debug   ] Launching MSI installation via msiexec.exe with arguments: /i "C:\Program Files\IntuneApps\MyApp\setup.msi" /qn /norestart
2026-01-25 10:30:15 [  Debug   ] MSI installation process ID: 12360
2026-01-25 10:30:15 [  Info    ] MSI installation exit code: 0
2026-01-25 10:30:15 [  Success ] MSI installation completed successfully.
2026-01-25 10:30:15 [  Info    ] MSI installer process has completed. Verifying installation via registry detection...
2026-01-25 10:30:15 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:30:15 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:30:15 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:30:16 [  Info    ] Retry attempt 2 of 3 after 5 seconds...
2026-01-25 10:30:21 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:30:21 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:30:21 [  Success ] Match found for application: 'My Application'
2026-01-25 10:30:21 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:30:21 [  Info    ] Script execution time: 00:00:06.78
2026-01-25 10:30:21 [  Info    ] Exit Code: 0
2026-01-25 10:30:21 [  End     ] ======== Script Completed ========
```

### Example 5: MSI Installation with Exit Code 3010 (Reboot Required)

```
2026-01-25 10:35:20 [  Start   ] ======== Script Started ========
2026-01-25 10:35:20 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:35:20 [  Get     ] Validating installer path...
2026-01-25 10:35:20 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 10:35:20 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:35:20 [  Debug   ] Launching MSI installation via msiexec.exe with arguments: /i "C:\Program Files\IntuneApps\MyApp\setup.msi" /qn /norestart
2026-01-25 10:35:20 [  Debug   ] MSI installation process ID: 12365
2026-01-25 10:35:20 [  Info    ] MSI installation exit code: 3010
2026-01-25 10:35:20 [  Info    ] MSI installation completed successfully but reboot is required (exit code 3010).
2026-01-25 10:35:20 [  Info    ] MSI installer process has completed. Verifying installation via registry detection...
2026-01-25 10:35:20 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:35:20 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:35:20 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:35:21 [  Success ] Match found for application: 'My Application'
2026-01-25 10:35:21 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:35:21 [  Info    ] Script execution time: 00:00:01.67
2026-01-25 10:35:21 [  Info    ] Exit Code: 3010
2026-01-25 10:35:21 [  End     ] ======== Script Completed ========
```

### Example 6: MSI Installation with Non-Zero Exit Code (But Verification Succeeds)

```
2026-01-25 10:40:10 [  Start   ] ======== Script Started ========
2026-01-25 10:40:10 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:40:10 [  Get     ] Validating installer path...
2026-01-25 10:40:10 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 10:40:10 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:40:10 [  Debug   ] Launching MSI installation via msiexec.exe with arguments: /i "C:\Program Files\IntuneApps\MyApp\setup.msi" /qn /norestart
2026-01-25 10:40:10 [  Debug   ] MSI installation process ID: 12370
2026-01-25 10:40:10 [  Info    ] MSI installation exit code: 1603
2026-01-25 10:40:10 [  Info    ] MSI installation returned exit code: 1603
2026-01-25 10:40:10 [  Info    ] MSI installer process has completed. Verifying installation via registry detection...
2026-01-25 10:40:10 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 10:40:10 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 10:40:10 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 10:40:11 [  Success ] Match found for application: 'My Application'
2026-01-25 10:40:11 [  Success ] My Application is installed and verified in registry.
2026-01-25 10:40:11 [  Info    ] Script execution time: 00:00:01.89
2026-01-25 10:40:11 [  Info    ] Exit Code: 1603
2026-01-25 10:40:11 [  End     ] ======== Script Completed ========
```

### Example 7: Installation Failure - Installer Not Found

```
2026-01-25 10:45:10 [  Start   ] ======== Script Started ========
2026-01-25 10:45:10 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:45:10 [  Get     ] Validating installer path...
2026-01-25 10:45:10 [  Error   ] Installer not found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 10:45:10 [  Info    ] Script execution time: 00:00:00.12
2026-01-25 10:45:10 [  Info    ] Exit Code: 1
2026-01-25 10:45:10 [  End     ] ======== Script Completed ========
```

### Example 8: Installation Failure - Application Name Not Configured (MSI)

```
2026-01-25 10:50:15 [  Start   ] ======== Script Started ========
2026-01-25 10:50:15 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: 
2026-01-25 10:50:15 [  Error   ] Application name is not configured. Please set `$applicationName.
2026-01-25 10:50:15 [  Info    ] Script execution time: 00:00:00.05
2026-01-25 10:50:15 [  Info    ] Exit Code: 1
2026-01-25 10:50:15 [  End     ] ======== Script Completed ========
```

### Example 9: Installation Failure - MSI Arguments Construction Failed

```
2026-01-25 10:55:20 [  Start   ] ======== Script Started ========
2026-01-25 10:55:20 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 10:55:20 [  Get     ] Validating installer path...
2026-01-25 10:55:20 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 10:55:20 [  Run     ] Starting installation for 'My Application'.
2026-01-25 10:55:20 [  Error   ] InstallerPath is empty or null. Cannot construct MSI arguments.
2026-01-25 10:55:20 [  Error   ] Failed to construct MSI arguments. Installation cannot proceed.
2026-01-25 10:55:20 [  Info    ] Script execution time: 00:00:00.34
2026-01-25 10:55:20 [  Info    ] Exit Code: 1
2026-01-25 10:55:20 [  End     ] ======== Script Completed ========
```

### Example 10: Installation Failure - Process Exception

```
2026-01-25 11:00:25 [  Start   ] ======== Script Started ========
2026-01-25 11:00:25 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:00:25 [  Get     ] Validating installer path...
2026-01-25 11:00:25 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 11:00:25 [  Run     ] Starting installation for 'My Application'.
2026-01-25 11:00:25 [  Debug   ] Launching process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' with arguments: /silent
2026-01-25 11:00:25 [  Error   ] Exception during installation: Access is denied
2026-01-25 11:00:25 [  Debug   ] Exception details: System.UnauthorizedAccessException: Access is denied
2026-01-25 11:00:25 [  Info    ] Script execution time: 00:00:00.45
2026-01-25 11:00:25 [  Info    ] Exit Code: 1
2026-01-25 11:00:25 [  End     ] ======== Script Completed ========
```

### Example 11: Installation Failure - Process Returned Null (EXE)

```
2026-01-25 11:05:30 [  Start   ] ======== Script Started ========
2026-01-25 11:05:30 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:05:30 [  Get     ] Validating installer path...
2026-01-25 11:05:30 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 11:05:30 [  Run     ] Starting installation for 'My Application'.
2026-01-25 11:05:30 [  Debug   ] Launching process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' with arguments: /silent
2026-01-25 11:05:30 [  Error   ] Start-Process did not return a process object. Installation may have failed to start.
2026-01-25 11:05:30 [  Info    ] Installer process has completed. Verifying installation via registry detection...
2026-01-25 11:05:30 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 11:05:30 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:05:30 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:05:31 [  Info    ] Retry attempt 2 of 3 after 5 seconds...
2026-01-25 11:05:36 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:05:36 [  Info    ] Retry attempt 3 of 3 after 5 seconds...
2026-01-25 11:05:41 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:05:41 [  Error   ] My Application was not found in registry after 3 attempts. Installation may have failed.
2026-01-25 11:05:41 [  Info    ] Script execution time: 00:00:16.12
2026-01-25 11:05:41 [  Info    ] Exit Code: 1
2026-01-25 11:05:41 [  End     ] ======== Script Completed ========
```

### Example 12: Installation Failure - Verification Failed After All Retries

```
2026-01-25 11:10:35 [  Start   ] ======== Script Started ========
2026-01-25 11:10:35 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:10:35 [  Get     ] Validating installer path...
2026-01-25 11:10:35 [  Success ] Installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 11:10:35 [  Run     ] Starting installation for 'My Application'.
2026-01-25 11:10:35 [  Debug   ] Launching process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' with arguments: /silent
2026-01-25 11:10:35 [  Debug   ] Installer process ID: 12380
2026-01-25 11:10:40 [  Info    ] Installer process has completed. Verifying installation via registry detection...
2026-01-25 11:10:40 [  Info    ] Waiting for registry keys to be populated...
2026-01-25 11:10:40 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:10:40 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:10:40 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:10:41 [  Info    ] Retry attempt 2 of 3 after 5 seconds...
2026-01-25 11:10:46 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:10:46 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:10:46 [  Info    ] Retry attempt 3 of 3 after 5 seconds...
2026-01-25 11:10:51 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 11:10:51 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:10:51 [  Debug   ] Found 89 subkeys under: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:10:52 [  Error   ] My Application was not found in registry after 3 attempts. Installation may have failed.
2026-01-25 11:10:52 [  Info    ] Script execution time: 00:00:17.23
2026-01-25 11:10:52 [  Info    ] Exit Code: 1
2026-01-25 11:10:52 [  End     ] ======== Script Completed ========
```

---

## 🗑️ Uninstall Script Log Examples

### Example 13: Successful Uninstall - Packaged Uninstaller (EXE)

```
2026-01-25 11:15:40 [  Start   ] ======== Script Started ========
2026-01-25 11:15:40 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:15:40 [  Info    ] Configured to use packaged installer for uninstall.
2026-01-25 11:15:40 [  Get     ] Validating installer path...
2026-01-25 11:15:40 [  Success ] Packaged installer found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 11:15:40 [  Debug   ] Detected packaged installer extension: '.exe'
2026-01-25 11:15:40 [  Info    ] Packaged installer identified as EXE. Using EXE uninstall arguments.
2026-01-25 11:15:40 [  Run     ] Starting Packaged uninstall process: 'C:\Program Files\IntuneApps\MyApp\setup.exe' /uninstall /silent
2026-01-25 11:15:40 [  Debug   ] Packaged uninstall process ID: 12385
2026-01-25 11:15:45 [  Info    ] Packaged uninstall exit code: 0
2026-01-25 11:15:45 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:15:45 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:15:45 [  Info    ] Application still present in registry (validation check 1 of 3).
2026-01-25 11:15:50 [  Info    ] Validation check 2 of 3 after 5 seconds...
2026-01-25 11:15:50 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:15:50 [  Info    ] Script execution time: 00:00:10.67
2026-01-25 11:15:50 [  Info    ] Exit Code: 0
2026-01-25 11:15:50 [  End     ] ======== Script Completed ========
```

### Example 14: Successful Uninstall - Packaged Uninstaller (MSI)

```
2026-01-25 11:20:45 [  Start   ] ======== Script Started ========
2026-01-25 11:20:45 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:20:45 [  Info    ] Configured to use packaged installer for uninstall.
2026-01-25 11:20:45 [  Get     ] Validating installer path...
2026-01-25 11:20:45 [  Success ] Packaged installer found at path: C:\Program Files\IntuneApps\MyApp\setup.msi
2026-01-25 11:20:45 [  Debug   ] Detected packaged installer extension: '.msi'
2026-01-25 11:20:45 [  Info    ] Packaged installer identified as MSI. Preparing msiexec uninstall command line.
2026-01-25 11:20:45 [  Run     ] Starting Packaged uninstall process: 'msiexec.exe' /x "C:\Program Files\IntuneApps\MyApp\setup.msi" /qn
2026-01-25 11:20:45 [  Debug   ] Packaged uninstall process ID: 12390
2026-01-25 11:20:45 [  Info    ] Packaged uninstall exit code: 0
2026-01-25 11:20:45 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:20:45 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:20:45 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:20:45 [  Info    ] Script execution time: 00:00:00.89
2026-01-25 11:20:45 [  Info    ] Exit Code: 0
2026-01-25 11:20:45 [  End     ] ======== Script Completed ========
```

### Example 15: Successful Uninstall - Registry-Based (EXE)

```
2026-01-25 11:25:50 [  Start   ] ======== Script Started ========
2026-01-25 11:25:50 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:25:50 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:25:50 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:25:50 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:25:50 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:25:50 [  Debug   ] Found installed product: 'My Application'
2026-01-25 11:25:50 [  Success ] Found application 'My Application'
2026-01-25 11:25:50 [  Debug   ] Original uninstall string: "C:\Program Files\MyApp\uninstall.exe" /S
2026-01-25 11:25:50 [  Info    ] Non-MSI uninstaller detected. Checking if EXE uninstall arguments are needed.
2026-01-25 11:25:50 [  Debug   ] Appended EXE uninstall arguments: /uninstall /silent
2026-01-25 11:25:50 [  Debug   ] Final uninstall string: "C:\Program Files\MyApp\uninstall.exe" /S /uninstall /silent
2026-01-25 11:25:50 [  Debug   ] Parsed uninstaller path: C:\Program Files\MyApp\uninstall.exe
2026-01-25 11:25:50 [  Debug   ] Parsed uninstaller arguments: /S /uninstall /silent
2026-01-25 11:25:50 [  Run     ] Starting Registry-based uninstall process: 'C:\Program Files\MyApp\uninstall.exe' /S /uninstall /silent
2026-01-25 11:25:50 [  Debug   ] Registry-based uninstall process ID: 12395
2026-01-25 11:25:55 [  Info    ] Registry-based uninstall exit code: 0
2026-01-25 11:25:55 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:25:55 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:25:55 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:25:55 [  Info    ] Script execution time: 00:00:05.34
2026-01-25 11:25:55 [  Info    ] Exit Code: 0
2026-01-25 11:25:55 [  End     ] ======== Script Completed ========
```

### Example 16: Successful Uninstall - Registry-Based (MSI)

```
2026-01-25 11:30:55 [  Start   ] ======== Script Started ========
2026-01-25 11:30:55 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:30:55 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:30:55 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:30:55 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:30:55 [  Success ] Found application 'My Application'
2026-01-25 11:30:55 [  Debug   ] Original uninstall string: msiexec.exe /x{12345678-1234-1234-1234-123456789ABC} /qn
2026-01-25 11:30:55 [  Info    ] MSI-based uninstaller detected. Ensuring MSI uninstall arguments are present.
2026-01-25 11:30:55 [  Debug   ] MSI uninstall string already contains quiet flag.
2026-01-25 11:30:55 [  Debug   ] Final uninstall string: msiexec.exe /x{12345678-1234-1234-1234-123456789ABC} /qn
2026-01-25 11:30:55 [  Debug   ] Parsed uninstaller path: C:\Windows\System32\msiexec.exe
2026-01-25 11:30:55 [  Debug   ] Parsed uninstaller arguments: /x{12345678-1234-1234-1234-123456789ABC} /qn
2026-01-25 11:30:55 [  Run     ] Starting Registry-based uninstall process: 'C:\Windows\System32\msiexec.exe' /x{12345678-1234-1234-1234-123456789ABC} /qn
2026-01-25 11:30:55 [  Debug   ] Registry-based uninstall process ID: 12400
2026-01-25 11:30:55 [  Info    ] Registry-based uninstall exit code: 0
2026-01-25 11:30:55 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:30:55 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:30:55 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:30:55 [  Info    ] Script execution time: 00:00:00.67
2026-01-25 11:30:55 [  Info    ] Exit Code: 0
2026-01-25 11:30:55 [  End     ] ======== Script Completed ========
```

### Example 17: Successful Uninstall with Retry Validation

```
2026-01-25 11:35:00 [  Start   ] ======== Script Started ========
2026-01-25 11:35:00 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:35:00 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:35:00 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:35:00 [  Success ] Found application 'My Application'
2026-01-25 11:35:00 [  Run     ] Starting Registry-based uninstall process: 'C:\Program Files\MyApp\uninstall.exe' /S /uninstall /silent
2026-01-25 11:35:00 [  Debug   ] Registry-based uninstall process ID: 12405
2026-01-25 11:35:05 [  Info    ] Registry-based uninstall exit code: 0
2026-01-25 11:35:05 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:35:05 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:35:05 [  Info    ] Application still present in registry (validation check 1 of 3).
2026-01-25 11:35:10 [  Info    ] Validation check 2 of 3 after 5 seconds...
2026-01-25 11:35:10 [  Info    ] Application still present in registry (validation check 2 of 3).
2026-01-25 11:35:15 [  Info    ] Validation check 3 of 3 after 5 seconds...
2026-01-25 11:35:15 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:35:15 [  Info    ] Script execution time: 00:00:15.89
2026-01-25 11:35:15 [  Info    ] Exit Code: 0
2026-01-25 11:35:15 [  End     ] ======== Script Completed ========
```

### Example 18: Uninstall with Exit Code 3010 (Reboot Required)

```
2026-01-25 11:40:05 [  Start   ] ======== Script Started ========
2026-01-25 11:40:05 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:40:05 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:40:05 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:40:05 [  Success ] Found application 'My Application'
2026-01-25 11:40:05 [  Run     ] Starting Registry-based uninstall process: 'C:\Windows\System32\msiexec.exe' /x{12345678-1234-1234-1234-123456789ABC} /qn
2026-01-25 11:40:05 [  Debug   ] Registry-based uninstall process ID: 12410
2026-01-25 11:40:05 [  Info    ] Registry-based uninstall exit code: 3010
2026-01-25 11:40:05 [  Info    ] Uninstall completed but reboot is required (exit code 3010).
2026-01-25 11:40:05 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:40:05 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:40:05 [  Info    ] Script execution time: 00:00:00.78
2026-01-25 11:40:05 [  Info    ] Exit Code: 3010
2026-01-25 11:40:05 [  End     ] ======== Script Completed ========
```

### Example 19: Uninstall Failure - Application Not Found in Registry

```
2026-01-25 11:45:10 [  Start   ] ======== Script Started ========
2026-01-25 11:45:10 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:45:10 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:45:10 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:45:10 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:45:10 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 11:45:10 [  Error   ] Application 'My Application' not found in registry or UninstallString is missing.
2026-01-25 11:45:10 [  Info    ] Script execution time: 00:00:00.45
2026-01-25 11:45:10 [  Info    ] Exit Code: 1
2026-01-25 11:45:10 [  End     ] ======== Script Completed ========
```

### Example 20: Uninstall Failure - Packaged Uninstaller Not Found

```
2026-01-25 11:50:15 [  Start   ] ======== Script Started ========
2026-01-25 11:50:15 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:50:15 [  Info    ] Configured to use packaged installer for uninstall.
2026-01-25 11:50:15 [  Get     ] Validating installer path...
2026-01-25 11:50:15 [  Error   ] Packaged installer not found at path: C:\Program Files\IntuneApps\MyApp\setup.exe
2026-01-25 11:50:15 [  Info    ] Script execution time: 00:00:00.23
2026-01-25 11:50:15 [  Info    ] Exit Code: 1
2026-01-25 11:50:15 [  End     ] ======== Script Completed ========
```

### Example 21: Uninstall Failure - Validation Failed, Fallback Successful

```
2026-01-25 11:55:20 [  Start   ] ======== Script Started ========
2026-01-25 11:55:20 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 11:55:20 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 11:55:20 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:55:20 [  Success ] Found application 'My Application'
2026-01-25 11:55:20 [  Run     ] Starting Registry-based uninstall process: 'C:\Program Files\MyApp\uninstall.exe' /S
2026-01-25 11:55:20 [  Debug   ] Registry-based uninstall process ID: 12415
2026-01-25 11:55:25 [  Info    ] Registry-based uninstall exit code: 0
2026-01-25 11:55:25 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 11:55:25 [  Info    ] Performing post-uninstall validation...
2026-01-25 11:55:25 [  Info    ] Application still present in registry (validation check 1 of 3).
2026-01-25 11:55:30 [  Info    ] Validation check 2 of 3 after 5 seconds...
2026-01-25 11:55:30 [  Info    ] Application still present in registry (validation check 2 of 3).
2026-01-25 11:55:35 [  Info    ] Validation check 3 of 3 after 5 seconds...
2026-01-25 11:55:35 [  Info    ] Application still present in registry (validation check 3 of 3).
2026-01-25 11:55:35 [  Error   ] Uninstall process completed but validation failed.
2026-01-25 11:55:35 [  Info    ] Attempting fallback: Searching for alternative UninstallString...
2026-01-25 11:55:35 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 11:55:35 [  Info    ] Found alternative UninstallString. Executing fallback uninstall...
2026-01-25 11:55:35 [  Debug   ] Alternative UninstallString: "C:\Program Files\MyApp\uninstall2.exe" /SILENT
2026-01-25 11:55:35 [  Run     ] Starting Fallback uninstall process: 'C:\Program Files\MyApp\uninstall2.exe' /SILENT
2026-01-25 11:55:35 [  Debug   ] Fallback uninstall process ID: 12420
2026-01-25 11:55:40 [  Info    ] Fallback uninstall exit code: 0
2026-01-25 11:55:40 [  Success ] Fallback uninstall completed with exit code: 0
2026-01-25 11:55:40 [  Info    ] Re-validating after fallback uninstall...
2026-01-25 11:55:40 [  Success ] Post-uninstall validation successful: Application removed from registry.
2026-01-25 11:55:40 [  Success ] Fallback uninstall and validation successful.
2026-01-25 11:55:40 [  Info    ] Script execution time: 00:00:20.67
2026-01-25 11:55:40 [  Info    ] Exit Code: 0
2026-01-25 11:55:40 [  End     ] ======== Script Completed ========
```

### Example 22: Uninstall Failure - Validation Failed, No Fallback Available

```
2026-01-25 12:00:25 [  Start   ] ======== Script Started ========
2026-01-25 12:00:25 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:00:25 [  Info    ] Using registry-based uninstall (UninstallString) for 'My Application'.
2026-01-25 12:00:25 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 12:00:25 [  Success ] Found application 'My Application'
2026-01-25 12:00:25 [  Run     ] Starting Registry-based uninstall process: 'C:\Program Files\MyApp\uninstall.exe' /S
2026-01-25 12:00:25 [  Debug   ] Registry-based uninstall process ID: 12425
2026-01-25 12:00:30 [  Info    ] Registry-based uninstall exit code: 0
2026-01-25 12:00:30 [  Success ] My Application uninstall process completed with exit code: 0
2026-01-25 12:00:30 [  Info    ] Performing post-uninstall validation...
2026-01-25 12:00:30 [  Info    ] Application still present in registry (validation check 1 of 3).
2026-01-25 12:00:35 [  Info    ] Validation check 2 of 3 after 5 seconds...
2026-01-25 12:00:35 [  Info    ] Application still present in registry (validation check 2 of 3).
2026-01-25 12:00:40 [  Info    ] Validation check 3 of 3 after 5 seconds...
2026-01-25 12:00:40 [  Info    ] Application still present in registry (validation check 3 of 3).
2026-01-25 12:00:40 [  Error   ] Uninstall process completed but validation failed.
2026-01-25 12:00:40 [  Info    ] Attempting fallback: Searching for alternative UninstallString...
2026-01-25 12:00:40 [  Get     ] Searching registry for application 'My Application'...
2026-01-25 12:00:40 [  Error   ] No alternative UninstallString found. Validation failed.
2026-01-25 12:00:40 [  Info    ] Script execution time: 00:00:15.89
2026-01-25 12:00:40 [  Info    ] Exit Code: 1
2026-01-25 12:00:40 [  End     ] ======== Script Completed ========
```

### Example 23: Uninstall Failure - Unsupported Packaged Installer Extension

```
2026-01-25 12:05:30 [  Start   ] ======== Script Started ========
2026-01-25 12:05:30 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:05:30 [  Info    ] Configured to use packaged installer for uninstall.
2026-01-25 12:05:30 [  Get     ] Validating installer path...
2026-01-25 12:05:30 [  Success ] Packaged installer found at path: C:\Program Files\IntuneApps\MyApp\setup.zip
2026-01-25 12:05:30 [  Debug   ] Detected packaged installer extension: '.zip'
2026-01-25 12:05:30 [  Error   ] Unsupported packaged installer extension '.zip'. Only .exe and .msi are supported.
2026-01-25 12:05:30 [  Info    ] Script execution time: 00:00:00.34
2026-01-25 12:05:30 [  Info    ] Exit Code: 1
2026-01-25 12:05:30 [  End     ] ======== Script Completed ========
```

---

## 🔍 Detection Script Log Examples

### Example 24: Detection with Version Check - Success

```
2026-01-25 12:10:35 [  Start   ] ========== Detection Script ==========
2026-01-25 12:10:35 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:10:35 [  Debug   ] Target application: 'My Application' Version: '1.9.18'
2026-01-25 12:10:35 [  Debug   ] Log file: 'C:\ProgramData\IntuneLogs\Applications\My Application\detection.log'
2026-01-25 12:10:35 [  Get     ] Checking registry for application 'My Application' Version '1.9.18'.
2026-01-25 12:10:35 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:10:35 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:10:36 [  Debug   ] Found product: 'My Application' Version: '1.9.18'
2026-01-25 12:10:36 [  Success ] Match found: My Application (1.9.18)
2026-01-25 12:10:36 [  Success ] My Application Version 1.9.18 is installed.
2026-01-25 12:10:36 [  Info    ] Script execution time: 00:00:01.23
2026-01-25 12:10:36 [  Info    ] Exit Code: 0
2026-01-25 12:10:36 [  End     ] ========== Script Completed ==========
```

### Example 25: Detection with Version Check - Wrong Version

```
2026-01-25 12:15:40 [  Start   ] ========== Detection Script ==========
2026-01-25 12:15:40 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:15:40 [  Get     ] Checking registry for application 'My Application' Version '1.9.18'.
2026-01-25 12:15:40 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:15:40 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:15:41 [  Debug   ] Found product: 'My Application' Version: '1.9.17'
2026-01-25 12:15:42 [  Error   ] My Application Version 1.9.18 is NOT installed.
2026-01-25 12:15:42 [  Info    ] Script execution time: 00:00:01.89
2026-01-25 12:15:42 [  Info    ] Exit Code: 1
2026-01-25 12:15:42 [  End     ] ========== Script Completed ==========
```

### Example 26: Detection with Version Check - Application Not Found

```
2026-01-25 12:20:45 [  Start   ] ========== Detection Script ==========
2026-01-25 12:20:45 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:20:45 [  Get     ] Checking registry for application 'My Application' Version '1.9.18'.
2026-01-25 12:20:45 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:20:45 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:20:46 [  Debug   ] Found 89 subkeys under: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:20:47 [  Error   ] My Application Version 1.9.18 is NOT installed.
2026-01-25 12:20:47 [  Info    ] Script execution time: 00:00:02.34
2026-01-25 12:20:47 [  Info    ] Exit Code: 1
2026-01-25 12:20:47 [  End     ] ========== Script Completed ==========
```

### Example 27: Detection without Version Check - Success

```
2026-01-25 12:25:50 [  Start   ] ========== Detection Script ==========
2026-01-25 12:25:50 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:25:50 [  Debug   ] Target application (DisplayName match only): 'My Application'
2026-01-25 12:25:50 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 12:25:50 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:25:50 [  Debug   ] Found 156 subkeys under: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:25:51 [  Debug   ] Found product: 'My Application'
2026-01-25 12:25:51 [  Success ] Match found for application: 'My Application'
2026-01-25 12:25:51 [  Success ] My Application is installed.
2026-01-25 12:25:51 [  Info    ] Script execution time: 00:00:01.12
2026-01-25 12:25:51 [  Info    ] Exit Code: 0
2026-01-25 12:25:51 [  End     ] ========== Script Completed ==========
```

### Example 28: Detection without Version Check - Application Not Found

```
2026-01-25 12:30:55 [  Start   ] ========== Detection Script ==========
2026-01-25 12:30:55 [  Info    ] ComputerName: DESKTOP-ABC123 | User: SYSTEM | App: My Application
2026-01-25 12:30:55 [  Get     ] Checking registry for application 'My Application'.
2026-01-25 12:30:55 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:30:55 [  Get     ] Searching in registry path: HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
2026-01-25 12:30:56 [  Error   ] My Application is NOT installed.
2026-01-25 12:30:56 [  Info    ] Script execution time: 00:00:01.67
2026-01-25 12:30:56 [  Info    ] Exit Code: 1
2026-01-25 12:30:56 [  End     ] ========== Script Completed ==========
```

---

## 🛠 Troubleshooting Tips

### ⚠️ Install Issues

* Double-check installer arguments (`/quiet`, `/qn`, `/silent`)
* Verify the installer file name matches `$installerName` exactly
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
* Ensure the `DisplayName` matches exactly (case-sensitive)
* For version detection, verify the `DisplayVersion` format matches exactly

### ⚠️ Logging Issues

* Ensure the log directory path is accessible: `C:\ProgramData\IntuneLogs\Applications\<applicationName>\`
* Check file permissions - scripts run as SYSTEM, so SYSTEM must have write access
* If logs aren't appearing, set `$enableLogFile = $true` and verify `$log = $true`
* Enable debug logging by setting `$logDebug = $true` for more detailed information

---
