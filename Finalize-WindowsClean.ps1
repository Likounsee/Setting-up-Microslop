#Requires -RunAsAdministrator
$loggingScript = Join-Path $PSScriptRoot "Common\Logging.ps1"
if (Test-Path -LiteralPath $loggingScript) {
    . $loggingScript
    Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name -LogDirectory (Join-Path $PSScriptRoot "Logs") | Out-Null
} else {
    Write-Warning "Shared logger not found at $loggingScript"
}
trap {
    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level ERROR -Message ("Unhandled terminating error: " + ($_ | Out-String).Trim())
    }
    throw
}
$serviceStateScript = Join-Path $PSScriptRoot "Common\ServiceState.ps1"
if (-not (Test-Path -LiteralPath $serviceStateScript)) { throw "Service-state helpers not found: $serviceStateScript" }
. $serviceStateScript
$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript
$registrySnapshot = @{}
$registryBackupDirectory = Join-Path $PSScriptRoot "Backups\Registry"
$registryBackupName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$registryBackupFile = Join-Path $registryBackupDirectory $registryBackupName
$ErrorActionPreference = "SilentlyContinue"
$operationJournalScript = Join-Path $PSScriptRoot "Common\OperationJournal.ps1"
if (-not (Test-Path -LiteralPath $operationJournalScript)) { throw "Operation journal helpers not found: $operationJournalScript" }
. $operationJournalScript
$temporaryCleanupScript = Join-Path $PSScriptRoot "Common\TemporaryCleanup.ps1"
if (-not (Test-Path -LiteralPath $temporaryCleanupScript)) { throw "Temporary cleanup helpers not found: $temporaryCleanupScript" }
. $temporaryCleanupScript
$operationJournalDirectory = Join-Path $PSScriptRoot "Backups\Operations"
$operationJournalName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$operationJournalFile = Join-Path $operationJournalDirectory $operationJournalName
Write-Host "=== Final Tweaks (Privacy, File Extensions, 1:1 Mouse & Disk Cleanup) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Locking down sensor permissions, diagnostics, and lock screen Spotlight"
Write-Host "[1/3] Locking down sensor permissions, diagnostics, and lock screen Spotlight..." -ForegroundColor Yellow
$ap = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; New-Item -Path $ap -Force | Out-Null
Set-ProjectRegistryValue -Path $ap -Name "LetAppsAccessLocation" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $ap -Name "LetAppsGetDiagnosticInfo" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $ap -Name "LetAppsSyncWithDevices" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$ss = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"; New-Item -Path $ss -Force | Out-Null
Set-ProjectRegistryValue -Path $ss -Name "DisableSettingSync" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $ss -Name "DisableSettingSyncUserOverride" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; New-Item -Path $cdm -Force | Out-Null
Set-ProjectRegistryValue -Path $cdm -Name "RotatingLockScreenEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $cdm -Name "RotatingLockScreenOverlayEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; New-Item -Path $cc -Force | Out-Null
Set-ProjectRegistryValue -Path $cc -Name "DisableWindowsSpotlightFeatures" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile

Write-ProjectLog -Level INFO -Message "Showing file extensions/hidden files and disabling mouse acceleration"
Write-Host "[2/3] Showing file extensions/hidden files and disabling mouse acceleration..." -ForegroundColor Yellow
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; New-Item -Path $adv -Force | Out-Null
Set-ProjectRegistryValue -Path $adv -Name "HideFileExt" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $adv -Name "Hidden" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$mp = "HKCU:\Control Panel\Mouse"
Set-ProjectRegistryValue -Path $mp -Name "MouseSpeed" -Value "0" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $mp -Name "MouseThreshold1" -Value "0" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $mp -Name "MouseThreshold2" -Value "0" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class MouseHelper { [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d); }'
[MouseHelper]::SystemParametersInfo(0x0004, 0, @(0, 0, 0), 3) | Out-Null

Write-ProjectLog -Level INFO -Message "Optional age-limited temporary cleanup, Windows Update cache cleanup, and WinSxS maintenance"
Write-Host "[3/3] Optional temporary and component-store maintenance..." -ForegroundColor Yellow
$temporaryPaths = @($env:TEMP, (Join-Path $env:SystemRoot "Temp")) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
if ((Read-Host "Remove temporary entries older than 7 days from approved TEMP folders? [y/N]").Trim() -match "^(?i)y(es)?$") {
    foreach ($temporaryPath in $temporaryPaths) {
        try {
            $cleanup = Remove-ProjectStaleTemporaryItems -Path $temporaryPath -AllowedPaths $temporaryPaths -JournalPath $operationJournalFile -MinimumAgeDays 7
            Write-Host ("      {0}: removed {1}, skipped {2}, failed {3}" -f $temporaryPath, $cleanup.Removed, $cleanup.Skipped, $cleanup.Failed) -ForegroundColor Gray
        } catch {
            Write-ProjectLog -Level WARNING -Message ("Temporary cleanup was not completed for {0}: {1}" -f $temporaryPath, $_.Exception.Message)
        }
    }
} else {
    Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "Temporary cleanup" -Category Regenerable -Status Skipped -Details "User declined temporary cleanup." | Out-Null
}
$serviceNames = @("wuauserv", "bits", "dosvc")
$serviceWasRunning = @{}
foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        $serviceWasRunning[$name] = ($svc.Status -eq "Running")
    }
}
$serviceBackupDirectory = Join-Path $PSScriptRoot "Backups\Services"
$serviceBackupName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$serviceBackupFile = Join-Path $serviceBackupDirectory $serviceBackupName
Save-ProjectServiceSnapshot -WasRunning $serviceWasRunning -Path $serviceBackupFile | Out-Null
Write-Host "Service-state backup saved: $serviceBackupFile" -ForegroundColor Cyan
foreach ($name in $serviceWasRunning.Keys) {
    if ($serviceWasRunning[$name]) { Stop-Service -Name $name -Force -ErrorAction Stop }
}
try {
    if ((Read-Host "Clear regenerable Windows Update download caches? [y/N]").Trim() -match "^(?i)y(es)?$") {
        foreach ($cachePath in @("$env:SystemRoot\SoftwareDistribution\Download", "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization")) {
            if (Test-Path -LiteralPath $cachePath -PathType Container) {
                Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "Windows Update cache cleanup" -Category Regenerable -Status Started -Target $cachePath -Details "Cache contents are regenerable; contents are not backed up." | Out-Null
                try {
                    Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction Stop | Remove-Item -Recurse -Force -ErrorAction Stop
                    Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "Windows Update cache cleanup" -Category Regenerable -Status Completed -Target $cachePath -Details "Cache contents cleared; Windows can recreate them." | Out-Null
                } catch {
                    Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "Windows Update cache cleanup" -Category Regenerable -Status Failed -Target $cachePath -Details $_.Exception.Message | Out-Null
                    throw
                }
            }
        }
    } else {
        Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "Windows Update cache cleanup" -Category Regenerable -Status Skipped -Details "User declined cache cleanup." | Out-Null
    }
} finally {
    Restore-ProjectServiceStates -WasRunning $serviceWasRunning -ServiceNames $serviceNames
}
if ((Read-Host "Run DISM component-store cleanup? This operation is not reversible. [y/N]").Trim() -match "^(?i)y(es)?$") {
    Invoke-ProjectTrackedNativeCommand -FilePath "Dism.exe" -ArgumentList @("/Online", "/Cleanup-Image", "/StartComponentCleanup") -Operation "DISM component-store cleanup" -Category Irreversible -JournalPath $operationJournalFile -Target "$env:SystemRoot\WinSxS" -ContinueOnError | Out-Null
} else {
    Write-ProjectOperationRecord -JournalPath $operationJournalFile -Operation "DISM component-store cleanup" -Category Irreversible -Status Skipped -Target "$env:SystemRoot\WinSxS" -Details "User declined non-reversible component-store maintenance." | Out-Null
}
Write-Host "Operation journal saved: $operationJournalFile" -ForegroundColor Cyan
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Final tweaks applied and disk space cleaned. ===" -ForegroundColor Green