# AMD display stability settings. Registry changes are backed up before every write.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

#Requires -RunAsAdministrator

$loggingScript = Join-Path $PSScriptRoot "Common\Logging.ps1"
if (-not (Test-Path -LiteralPath $loggingScript)) { throw "Shared logger not found: $loggingScript" }
. $loggingScript
Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name -LogDirectory (Join-Path $PSScriptRoot "Logs") | Out-Null

$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript

$amdHelpers = Join-Path $PSScriptRoot "Common\AmdGpuStability.ps1"
if (-not (Test-Path -LiteralPath $amdHelpers)) { throw "AMD GPU stability helpers not found: $amdHelpers" }
. $amdHelpers

trap {
    Write-ProjectLog -Level ERROR -Message ("Unhandled terminating error: " + ($_ | Out-String).Trim())
    throw
}

$ErrorActionPreference = "Stop"
$registrySnapshot = @{}
$registryBackupDirectory = Join-Path $PSScriptRoot "Backups\Registry"
$registryBackupName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$registryBackupFile = Join-Path $registryBackupDirectory $registryBackupName

Write-Host "=== AMD GPU Display Stability Tweaks ===" -ForegroundColor Cyan
Write-ProjectLog -Level INFO -Message "Checking for an AMD display adapter before applying graphics registry tweaks."

$amdDevices = @(Get-ProjectAmdDisplayDevices)
if ($amdDevices.Count -eq 0) {
    Write-Host "No active AMD GPU detected. AMD stability tweaks skipped." -ForegroundColor Gray
    Write-ProjectLog -Level INFO -Message "No active AMD display adapter detected; no registry changes were made."
    Complete-ProjectLogging -Message "AMD GPU stability module completed (not applicable)."
    return
}

foreach ($device in $amdDevices) {
    Write-Host ("AMD GPU detected: {0}" -f $device.FriendlyName) -ForegroundColor Green
    Write-ProjectLog -Level INFO -Message ("AMD display adapter detected: " + $device.FriendlyName)
}

Write-Host "[1/3] Disabling Multi-Plane Overlay (MPO)..." -ForegroundColor Yellow
Set-ProjectRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -Value 5 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile | Out-Null

Write-Host "[2/3] Disabling Hardware-Accelerated GPU Scheduling (HAGS)..." -ForegroundColor Yellow
Set-ProjectRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile | Out-Null

Write-Host "[3/3] Disabling ULPS on AMD adapter registry entries..." -ForegroundColor Yellow
$ulpsPaths = @(Get-ProjectAmdUlpsRegistryPaths)
foreach ($path in $ulpsPaths) {
    Set-ProjectRegistryValue -Path $path -Name "EnableUlps" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile | Out-Null
    Write-Host ("      ULPS disabled: {0}" -f $path) -ForegroundColor Green
}
if ($ulpsPaths.Count -eq 0) {
    Write-ProjectLog -Level WARNING -Message "No graphics adapter registry subkey containing EnableUlps was found; MPO and HAGS settings were still applied."
    Write-Host "      No EnableUlps value found; no ULPS entry needed changing." -ForegroundColor Gray
}

Write-ProjectLog -Level INFO -Message ("AMD graphics settings applied. ULPS adapter entries updated: {0}. Registry backup: {1}" -f $ulpsPaths.Count, $registryBackupFile)
Complete-ProjectLogging -Message "AMD GPU stability registry tweaks completed."
Write-Host "`n=== AMD GPU stability settings applied. Restart Windows to activate them. ===" -ForegroundColor Green
