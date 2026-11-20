# Setting-up-Microslop

Modular PowerShell automation suite to debloat, optimize, and configure fresh **Windows 10 / 11** installations with zero leftover files.

## Quick Start

Download the latest ZIP from GitHub, extract it, then **double-click `Run-Setup.cmd`**. You can also launch it from a terminal:

```powershell
.\Run-Setup.cmd
```

The launcher starts `Run-Setup.ps1`, requests UAC Administrator elevation when needed, and keeps the console open after completion so the final status and any errors remain visible. Logs and operation backups stay in the extracted folder.

If you prefer a PowerShell one-liner, use this version (it deliberately keeps the extracted folder so logs and recovery backups are not deleted):

```powershell
$tmp = Join-Path $env:TEMP ("microslop-" + (Get-Date -Format "yyyyMMdd-HHmmss")); $zip = "$tmp.zip"; New-Item -ItemType Directory -Path $tmp -Force | Out-Null; Invoke-RestMethod "https://github.com/Likounsee/Setting-up-Microslop/archive/refs/heads/main.zip" -OutFile $zip; Expand-Archive $zip -DestinationPath $tmp -Force; $dir = (Get-ChildItem $tmp -Directory)[0].FullName; & "$dir\Run-Setup.cmd"; Write-Host "Setup files, logs and backups retained at: $dir"
```

---

## Included Modules

| Script | Description |
| :--- | :--- |
| **`Run-Setup.cmd`** | Recommended Windows launcher; keeps the console open and displays the final exit code. |
| **`Run-Setup.ps1`** | Interactive orchestrator (`[Y/N]`) with automatic UAC Administrator elevation and detailed error reporting. |
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
& .\Run-Setup.cmd
```

## Safety notes

- Review every module before running it; these scripts make system-wide changes and require Administrator privileges.
- The OneDrive module now preserves `%USERPROFILE%\\OneDrive`. Check that folder and confirm cloud-only files are available before manually deleting or moving anything.
- The bloatware module uses Windows Appx removal commands and no longer takes ownership of or deletes files from `C:\\Program Files\\WindowsApps`.
- Disabling SysMain and hibernation is now opt-in in the optimization module. Keep the defaults unless you understand the trade-offs for your device.
- The final-cleanup module now asks before deleting temporary files, limits cleanup to entries older than seven days, and skips trees containing reparse points or newer nested data. Windows Update cache cleanup and DISM component-store cleanup are also opt-in.
- Non-reversible maintenance actions are recorded in a timestamped JSON operation journal under `Backups/Operations`. This is an audit trail, not a rollback mechanism. Windows Update caches are regenerable and are not backed up; DISM component-store cleanup cannot be undone.
- The cleanup module attempts to restore the original running/stopped state of Windows Update services after cache maintenance.
- These changes have been reviewed statically; they still need testing on clean Windows 10 and Windows 11 virtual machines before being considered production-ready.


## Development and tests

The repository includes 60 Pester test cases covering setup error classification and diagnostic formatting, shared logging, external-command exit codes and journaled exit codes, Appx inventory and recovery planning, auditable Appx removals, persistent operation journals, age-limited temporary cleanup, explicit temporary-path allowlists, guarded package-folder deletion, verified filesystem backup and restore, explicit cleanup allowlists, destination-collision protection, manifest/path validation, backup-integrity checks, restoration and persistence of Windows service states, registry value snapshots, recursive key-tree backups, and conflict-safe rollback.

Run the test suite locally from the repository root:

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester -Path ./Tests -Output Detailed
```

GitHub Actions runs PowerShell syntax parsing and Pester (including the setup diagnostics tests) on both PowerShell 7 (`pwsh`) and Windows PowerShell 5.1 (`powershell`) on Windows runners whenever `main` is updated, and for pull requests.


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

The restore script displays the number of entries and requires typing `RESTORE` before changing anything. It skips values changed since the backup and key trees recreated after removal; pass `-Force` only when you deliberately want to overwrite those newer values. For a recreated key tree, `-Force` deletes the current tree and rebuilds it from the backup, including removing values and subkeys added after the backup. Keep backup files private because they may contain previous Windows configuration values. Registry backups cover individual values changed through `Set-ProjectRegistryValue` and the two Explorer CLSID key trees removed by `Remove-OneDriveComplete.ps1`. A backup restores registry values only; it does not reinstall removed applications, restore deleted files, or reverse external commands and service changes.


### Service-state backup and recovery

`Finalize-WindowsClean.ps1` records the initial states of Windows Update services before stopping any of them. The dated JSON file is stored in `Backups/Services`. The module still attempts immediate restoration in its `finally` block; if Windows or PowerShell is interrupted before that runs, restore the recorded running services manually from an elevated PowerShell session:

```powershell
$backup = Get-ChildItem .\Backups\Services\Finalize-WindowsClean-*.json |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
.\Restore-ServiceBackup.ps1 -BackupPath $backup.FullName
```

The recovery script requires typing `RESTORE` and only starts services that were running when the backup was made. It does not stop services that were originally stopped.


### Filesystem backup and recovery

The bloatware module backs up each eligible direct-child directory under the current user's `%LOCALAPPDATA%\\Packages` before removing it. The OneDrive module also backs up only three explicitly allowlisted residual locations (`%LOCALAPPDATA%\\Microsoft\\OneDrive`, `%PROGRAMDATA%\\Microsoft OneDrive`, and `C:\\OneDriveTemp`) before cleanup. The user data folder `%USERPROFILE%\\OneDrive` remains excluded. Each operation gets its own folder under `Backups/FileSystem`, containing the copied directory and a JSON manifest with the original destination and SHA-256 hashes for every file. The source is removed only after the copy has been verified. Reparse points are refused to avoid following junctions or symbolic links. If removal partially fails, the verified backup is deliberately retained.

Restore from an elevated PowerShell session:

```powershell
$backup = Get-ChildItem .\\Backups\\FileSystem -Directory |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
.\\Restore-FileSystemBackup.ps1 -BackupDirectory $backup.FullName
```

The restore tool requires typing `RESTORE`, validates the manifest against the original parent directory, verifies the backup hashes, and never overwrites an existing destination. For OneDrive residual backups, the original parent directory is recorded in the manifest and used as the restore root. These backups preserve file contents and directory structure; they do not promise preservation of original ACLs, ownership, timestamps, or alternate data streams. They cover only package directories explicitly processed by the bloatware module and the three allowlisted OneDrive residual directories—not Appx uninstallations, provisioned-package removals, WindowsApps, the user OneDrive folder, or other system changes. Keep backups on a drive with enough free space; this implementation copies data before deletion and may temporarily require roughly twice the folder's storage.



### Appx inventory and recovery assessment

Before the Edge, Xbox, or general bloatware modules remove Appx packages, they save an inventory under `Backups/Appx`. It records stable package identities and selected metadata for installed and provisioned packages. Each removal is separately recorded as started, completed, or failed in that module's operation journal. The inventory does **not** contain Appx package binaries and does not make removal reversible.

To compare a previous inventory with the current machine:

```powershell
.\Get-AppxRecoveryPlan.ps1 -InventoryPath .\Backups\Appx\Remove-WindowsBloatware-YYYYMMDD-HHMMSS-xxxxxxxx.json -CsvPath .\Backups\Appx\recovery-plan.csv
```

The report identifies packages that were present in the inventory but are no longer installed or provisioned. If the original install directory still exists, it suggests inspecting its `AppxManifest.xml`; otherwise it points to Microsoft Store Library, the original vendor installer, or matching Windows installation media. This is an assessment only: it never downloads or installs packages automatically. Some inbox packages can only be restored from a matching Windows image or trusted package source, and availability varies by Windows build.

### Maintenance operation journal

`Finalize-WindowsClean.ps1` writes an operation journal to `Backups/Operations`. It records whether maintenance actions were started, completed, failed, or skipped, along with the target, command details, timestamps, and native exit codes where available. Temporary cleanup is limited to top-level entries older than seven days in the explicitly approved TEMP directories; a directory is skipped if it contains newer data or a reparse point. Windows Update download caches are treated as regenerable data and are only cleared after confirmation. DISM component-store cleanup also requires confirmation and is marked as irreversible in the journal.

The journal helps diagnose what the script actually attempted. It does not restore temporary files, rebuild Windows Update caches immediately, reinstall removed Appx packages, or reverse DISM changes. External-command journal records omit raw arguments; the regular execution log may still contain command lines. Windows recreates update caches as needed.

## Notes

- **Encoding:** All `.ps1` files are saved in **UTF-8 with BOM** for full compatibility with Windows PowerShell 5.1 and PowerShell 7+.
- **Reboot:** Restart your system after execution to finalize service, policy, and Explorer changes.