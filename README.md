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


## Development and tests

The repository includes 30 Pester test cases covering shared logging, external-command exit codes, guarded package-folder deletion, restoration and persistence of Windows service states, registry value snapshots, recursive key-tree backups, and conflict-safe rollback.

Run the test suite locally from the repository root:

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester -Path ./Tests -Output Detailed
```

GitHub Actions runs PowerShell syntax parsing and Pester on both PowerShell 7 (`pwsh`) and Windows PowerShell 5.1 (`powershell`) on Windows runners whenever `main` is updated, and for pull requests.


### Registry backup and restoration

Each module that changes registry values writes or refreshes a dated JSON backup in `Backups/Registry` **before every registry mutation**. If a module is interrupted, the latest completed backup therefore still contains the original value and the intended value for conflict detection. Backups preserve the previous value, whether it existed, and its registry type. Binary values are encoded as Base64; registry data values are not copied into application logs. OneDrive Explorer CLSID key trees are now captured recursively, including nested keys, empty keys, default values, and all supported value types, before removal. The backup format is version 3 and remains able to import version 1 and 2 value-only backups. If a key tree contains an unsupported registry value type, removal is refused before any deletion rather than creating an incomplete backup.

To restore a backup from an elevated PowerShell session:

```powershell
$backup = Get-ChildItem .\Backups\Registry\Optimize-WindowsSystem-*.json |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
.\Restore-RegistryBackup.ps1 -BackupPath $backup.FullName

# To override detected changes made since the backup:
.\Restore-RegistryBackup.ps1 -BackupPath $backup.FullName -Force
```

The restore script displays the number of entries and requires typing `RESTORE` before changing anything. It skips values changed since the backup and key trees recreated after removal; pass `-Force` only when you deliberately want to overwrite those newer values. Keep backup files private because they may contain previous Windows configuration values. Registry backups cover individual values changed through `Set-ProjectRegistryValue` and the two Explorer CLSID key trees removed by `Remove-OneDriveComplete.ps1`. A backup restores registry values only; it does not reinstall removed applications, restore deleted files, or reverse external commands and service changes.


### Service-state backup and recovery

`Finalize-WindowsClean.ps1` records the initial states of Windows Update services before stopping any of them. The dated JSON file is stored in `Backups/Services`. The module still attempts immediate restoration in its `finally` block; if Windows or PowerShell is interrupted before that runs, restore the recorded running services manually from an elevated PowerShell session:

```powershell
$backup = Get-ChildItem .\Backups\Services\Finalize-WindowsClean-*.json |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
.\Restore-ServiceBackup.ps1 -BackupPath $backup.FullName
```

The recovery script requires typing `RESTORE` and only starts services that were running when the backup was made. It does not stop services that were originally stopped.

## Notes

- **Encoding:** All `.ps1` files are saved in **UTF-8 with BOM** for full compatibility with Windows PowerShell 5.1 and PowerShell 7+.
- **Reboot:** Restart your system after execution to finalize service, policy, and Explorer changes.