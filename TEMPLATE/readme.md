# 🧠 **This Article Was Written With AI**

*(Generated automatically using ChatGPT.)*

---

# 🚀 Win32 App Deployment Framework for Microsoft Intune

This repository provides a **reusable, configurable, and standardized PowerShell deployment framework** for packaging, installing, uninstalling, and detecting Win32 applications in **Microsoft Intune**. 🎯

✅ Supports **EXE & MSI installers**
✅ Unified **logging**
✅ Registry **or** packaged uninstaller support

You can deploy **any Win32 application** by modifying just a few variables at the top of each 📜 script — no heavy rewrites needed.

---

## 📜 Included PowerShell Scripts

| 📜 Script Name                     | 📄 Purpose                                               |
| ---------------------------------- | -------------------------------------------------------- |
| `install.ps1`                      | Installs the packaged EXE/MSI silently                   |
| `uninstall.ps1`                    | Removes the application (packaged or registry uninstall) |
| `detectionWithVersionCheck.ps1`    | Detects application **and** version via registry         |
| `detectionWithoutVersionCheck.ps1` | Detects application via `DisplayName` only               |

> 🔍 **Note:** Detection 📜 scripts are **not** packaged into the `.intunewin` file. They are uploaded separately in Intune under **Detection rules**.

---

## ⚙️ `install.ps1` Overview 📜

### 🎯 Purpose

Silently installs an EXE or MSI included inside the Intune Win32 package.

### 🔧 Configuration (top of script)

```powershell
$applicationName  = "<Your Application Name>"

$installerName        = "<YourInstaller>.exe"     # or .msi
$installerPath        = Join-Path -Path $PSScriptRoot -ChildPath $installerName

$installerArgumentsExe = "/quiet"                 # Adjust to your app
$installerArgumentsMsi = "/qn"                    # Standard silent MSI install
```

### 🤖 Behavior

* ✅ Verifies that the installer 📄 exists at `$installerPath`
* ✅ Detects installer type by file extension (`.exe` / `.msi`)
* ✅ For MSI → runs `msiexec.exe /i "<path>" $installerArgumentsMsi`
* ✅ For EXE → runs `"<path>" $installerArgumentsExe`
* ✅ Logs all actions (arguments, PID, exit code)
* ✅ Exits with `0` on success, `1` on error (via `Stop-Script`)

### 📁 Log Location

```text
C:\ProgramData\IntuneLogs\Applications\<applicationName>\install.log
```

---

## 🗑️ `uninstall.ps1` Overview 📜

### 🎯 Purpose

Uninstalls the application using either:

* ✅ A **packaged EXE/MSI** included with the Win32 app (recommended), or
* ✅ The **registry UninstallString** entry

### 🔧 Configuration (top of script)

```powershell
$applicationName = "<Your Application Name>"

# Mode selection
$usePackagedUninstaller = $true   # $true = packaged uninstaller, $false = registry-based

# Packaged uninstaller
$installerName = "<YourInstaller>.exe"           # or .msi
$installerPath = Join-Path -Path $PSScriptRoot -ChildPath $installerName

# Uninstall arguments
$uninstallerArgumentsExe = "/uninstall /quiet /norestart"  # EXE
$uninstallerArgumentsMsi = "/qn"                           # MSI

# Registry search paths (only used when $usePackagedUninstaller = $false)
$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

### ✅ Mode A — Packaged Uninstaller (`$usePackagedUninstaller = $true`)

* 🔄 Skips registry lookup completely
* 🔍 Validates that the packaged uninstaller 📄 exists
* 🧠 Detects `.exe` or `.msi`
* ▶️ Runs:

  * MSI → `msiexec.exe /x "<path>" $uninstallerArgumentsMsi`
  * EXE → `"<path>" $uninstallerArgumentsExe`
* 🧾 Logs path, arguments, PID, and exit code
* 🚪 Exits with the process exit code (0 = success)

### ✅ Mode B — Registry-Based Uninstall (`$usePackagedUninstaller = $false`)

* 🔍 Searches uninstall registry keys for `DisplayName -eq $applicationName`
* 📖 Reads `UninstallString`
* 🧠 If `UninstallString` contains `msiexec.exe` → ensures `/qn` or `$uninstallerArgumentsMsi` is present
* 🧠 If non-MSI → appends `$uninstallerArgumentsExe`
* ▶️ Executes via:
  `cmd.exe /c "<uninstallString>"`

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
$applicationName    = "<Your Application Name>"
$applicationVersion = "<Your Version>"   # e.g. "1.9.18"

$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
```

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
$applicationName = "<Your Application Name>"

$registrySearchPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
)
```

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

```text
📁 C:\IntuneApps\<ApplicationName>
│
├─📜 install.ps1
├─📜 uninstall.ps1
└─📄 <YourInstaller>.exe / <YourInstaller>.msi
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

> 🧠 Remember: Detection 📜 scripts are **not** inside the `.intunewin` – you upload them separately.

#### Option A – Version-Based Detection

Use `detectionWithVersionCheck.ps1` 📜

* Rules format: **Use a custom detection script**
* Upload: `detectionWithVersionCheck.ps1`
* Exit codes:

  * `0` → application with correct version is installed
  * `1` → not installed / wrong version

#### Option B – Presence-Only Detection

Use `detectionWithoutVersionCheck.ps1` 📜

* Rules format: **Use a custom detection script**
* Upload: `detectionWithoutVersionCheck.ps1`
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
> The **📄 Log files** for all three scripts are saved at:
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
* `detecion.ps1` → `detection.log`

---

## 🛠 Troubleshooting Tips

### ⚠️ Install Issues

* Double-check installer arguments (`/quiet`, `/qn`)
* Turn on debug logging: set `$logDebug = $true` in the configuration section
* Run the installer manually with the same arguments to see vendor errors

### ⚠️ Uninstall Issues

* Verify whether `$usePackagedUninstaller` is set as intended
* If using registry mode, confirm the `DisplayName` exactly matches `$applicationName`
* Inspect the raw `UninstallString` on a test device and try it manually

### ⚠️ Detection Issues

* Run the detection 📜 scripts manually on a test device
* Confirm `DisplayName` / `DisplayVersion` in:

  * `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
  * `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`

---
