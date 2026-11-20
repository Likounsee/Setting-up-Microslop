# Setting-up-Microslop

Modular PowerShell automation suite to debloat, optimize, and configure fresh **Windows 10 / 11** installations with zero leftover files.

## Quick Start (One-Liner)

Open **PowerShell** (standard or Administrator) and run:

```powershell
$tmp = "$env:TEMP\microslop-$(Get-Random)"; $zip = "$tmp.zip"; try { Invoke-RestMethod "https://github.com/Likounsee/Setting-up-Microslop/archive/refs/heads/main.zip" -OutFile $zip; Expand-Archive $zip -DestinationPath $tmp -Force; $dir = (Get-ChildItem $tmp -Directory)[0].FullName; powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\Run-Setup.ps1" } finally { Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue }
```

This command automatically:
1. Downloads the latest repository archive into `%TEMP%`.
2. Launches `Run-Setup.ps1` with automatic UAC Administrator elevation.
3. Prompts `[Y/N]` for each module so you only run what you need.
4. Deletes all downloaded archives and extracted scripts upon exit.

---

## Included Modules

| Script | Description |
| :--- | :--- |
| **`Run-Setup.ps1`** | Interactive orchestrator (`[Y/N]`) with automatic UAC Administrator elevation. |
| **`Remove-EdgeKeepWebView.ps1`** | Uninstalls Microsoft Edge and blocks reinstallation via Windows Update policies while preserving and updating **WebView2 Runtime**. |
| **`Remove-OneDriveComplete.ps1`** | Completely uninstalls OneDrive, removes Explorer sidebar entries, blocks reinstallation, and restores `Desktop`, `Documents`, `Pictures`, `Music`, and `Videos` to local paths. |
| **`Remove-XboxComplete.ps1`** | Removes Xbox apps and Game Bar overlays, neutralizes `ms-gamebar` protocol pop-ups, and sets Xbox auth services to `Manual` so **Minecraft** login continues working. |
| **`Remove-WindowsBloatware.ps1`** | Disables Windows Recall, Copilot, and Widgets, uninstalls preinstalled bloatware, purges residual `AppData` caches, and blocks sponsored app suggestions. |
| **`Install-OfficeLight.ps1`** | Downloads the official Office Deployment Tool (ODT) and installs **Microsoft 365 ProPlus** containing **only Word, Excel, and PowerPoint** in a single chosen language (**French** or **English**). |
| **`Optimize-WindowsSystem.ps1`** | Disables telemetry/diagnostic tasks, Windows Update P2P (Delivery Optimization), `SysMain`, and hibernation (`hiberfil.sys`), and sets the power plan dynamically (**Balanced** on laptops, **High Performance** on desktops). |
| **`Finalize-WindowsClean.ps1`** | Locks down sensor/diagnostic permissions and lock screen Spotlight, reveals file extensions and hidden files, disables mouse acceleration (1:1 raw input), and cleans temporary files, update caches, and `WinSxS`. |

---

## Local Usage

If you prefer cloning the repository locally:

```powershell
git clone https://github.com/Likounsee/Setting-up-Microslop.git
cd Setting-up-Microslop
powershell -NoProfile -ExecutionPolicy Bypass -File .\Run-Setup.ps1
```

## Safety notes

- Review every module before running it; these scripts make system-wide changes and require Administrator privileges.
- The OneDrive module now preserves `%USERPROFILE%\\OneDrive`. Check that folder and confirm cloud-only files are available before manually deleting or moving anything.
- The bloatware module uses Windows Appx removal commands and no longer takes ownership of or deletes files from `C:\\Program Files\\WindowsApps`.
- Disabling SysMain and hibernation is now opt-in in the optimization module. Keep the defaults unless you understand the trade-offs for your device.
- The cleanup module attempts to restore the original running/stopped state of Windows Update services after clearing caches.
- These changes have been reviewed statically; they still need testing on clean Windows 10 and Windows 11 virtual machines before being considered production-ready.

## Notes

- **Encoding:** All `.ps1` files are saved in **UTF-8 with BOM** for full compatibility with Windows PowerShell 5.1 and PowerShell 7+.
- **Reboot:** Restart your system after execution to finalize service, policy, and Explorer changes.