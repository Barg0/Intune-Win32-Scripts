# Portable App Deployment (TeamViewerQS Example)

This package contains three PowerShell scripts for deploying a portable application (example: **TeamViewerQS.exe**) via Microsoft Intune as a Win32 application.

## Scripts

- **install.ps1**  
  Copies the packaged file into `%LocalAppData%\PortableApps\<AppName>`  
  Verifies the file with **SHA256 hash check**  
  Creates **Start Menu shortcut** (always) and optionally a **Desktop shortcut**  

- **detection.ps1**  
  Checks for:
  - The deployed file in `%LocalAppData%\PortableApps\<AppName>`
  - Start Menu shortcut
  - Desktop shortcut (only if enabled in config)

- **uninstall.ps1**  
  Removes:
  - Desktop shortcut (if present)  
  - Start Menu shortcut  
  - Deployed file  
  - Cleans up folder if empty  

## Configurable Variables

Each script includes a **config section** at the top:

```powershell
$localFolderName       = "PortableApps"
$fileName              = "TeamViewerQS.exe"
$fileSourcePath        = Join-Path -Path $PSScriptRoot -ChildPath $fileName
$shortcutName          = "TeamViewerQS"
$createDesktopShortcut = $true
$fileExpectedSHA256    = ""   # optional: auto-calculated if left empty
```

- **$localFolderName** → Subfolder inside `%LocalAppData%` where the app will be stored  
- **$fileName** → Name of the packaged file (must match your payload)  
- **$shortcutName** → Display name for the created shortcuts  
- **$createDesktopShortcut** → Set `true` or `false` depending if you want a desktop shortcut  
- **$fileExpectedSHA256** → Optional integrity check; leave blank to auto-derive from source  

## Extracting the File Hash

To enforce file integrity, you can calculate the **SHA256 hash** of your packaged file and paste it into `$fileExpectedSHA256`.

Run this PowerShell command:

```powershell
Get-FileHash -Path ".\TeamViewerQS.exe" -Algorithm SHA256
```

Example output:

```
Algorithm       Hash                                                                   Path
---------       ----                                                                   ----
SHA256          7F2E07B08D5F91C9E14CC3C5A47217F5F89E7D9CC8A73121F313D5E34BAA9A15       C:\Package\TeamViewerQS.exe
```

Copy the `Hash` value and assign it in your script:

```powershell
$fileExpectedSHA256 = "7F2E07B08D5F91C9E14CC3C5A47217F5F89E7D9CC8A73121F313D5E34BAA9A15"
```

If left empty (`""`), the script will automatically derive the hash from the packaged source file.

## Intune Win32 App Deployment

When publishing this app via Microsoft Intune as a **Win32 App**, use the following command lines:

- **Install command**  
  ```powershell
  powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File .\install.ps1
  ```

- **Uninstall command**  
  ```powershell
  powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File .\uninstall.ps1
  ```

- **Detection rule**  
  Use a **Custom Detection Script** and select `detection.ps1`.  

> ⚠️ **Important:** Make sure the **assignment type** is set to **"Required" for users** (not devices). These scripts deploy into the **current user profile** (`%LocalAppData%`, Desktop, Start Menu).  

## Notes

- Logging is written to  
  ```
  %ProgramData%\IntuneLogs\Applications\<Username>\<ApplicationName>\
  ```
- Logs include timestamps, tags (Info, Error, Success), and execution duration.  
- If the deployed file already exists and matches the expected SHA256 hash, the copy step is skipped.  
- If the hash differs, the file is overwritten with the packaged version.  

---

✅ This setup ensures reliable deployment of **portable apps** (like TeamViewer QuickSupport) without needing a traditional MSI/EXE installer.  
