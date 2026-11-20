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
$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript
$registrySnapshot = @{}
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== System Optimization (Telemetry, P2P, SysMain, Hibernation & Adaptive Power) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Disabling telemetry and diagnostic tasks"
Write-Host "[1/5] Disabling telemetry and diagnostic tasks..." -ForegroundColor Yellow
@("DiagTrack", "dmwappushservice") | ForEach-Object {
    if (Get-Service -Name $_ -ErrorAction SilentlyContinue) {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
        Set-ProjectRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$_" -Name "Start" -Value 4 -ValueKind DWord -Snapshot $registrySnapshot
    }
}
$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; New-Item -Path $dc -Force | Out-Null
Set-ProjectRegistryValue -Path $dc -Name "AllowTelemetry" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $dc -Name "DoNotShowFeedbackNotifications" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $dc -Name "DisableOneSettingsDownloads" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null
Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
$sp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; New-Item -Path $sp -Force | Out-Null
Set-ProjectRegistryValue -Path $sp -Name "EnableActivityFeed" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $sp -Name "PublishUserActivities" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $sp -Name "UploadUserActivities" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
@("\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser", "\Microsoft\Windows\Application Experience\ProgramDataUpdater", "\Microsoft\Windows\Application Experience\StartupAppTask", "\Microsoft\Windows\Autochk\Proxy", "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator", "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip", "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector", "\Microsoft\Windows\Feedback\Siuf\DmClient", "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload") | ForEach-Object {
    Invoke-ProjectNativeCommand -FilePath "schtasks.exe" -ArgumentList @("/Change", "/TN", "$_", "/DISABLE") -ContinueOnError | Out-Null
}

Write-ProjectLog -Level INFO -Message "Disabling Windows Update P2P"
Write-Host "[2/5] Disabling Windows Update P2P..." -ForegroundColor Yellow
$do1 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; New-Item -Path $do1 -Force | Out-Null
Set-ProjectRegistryValue -Path $do1 -Name "DODownloadMode" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
$do2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"; New-Item -Path $do2 -Force | Out-Null
Set-ProjectRegistryValue -Path $do2 -Name "DODownloadMode" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot

Write-ProjectLog -Level INFO -Message "Optional SysMain change"
Write-Host "[3/5] Optional SysMain change..." -ForegroundColor Yellow
if ((Read-Host "Disable SysMain? This can reduce performance on some PCs. [y/N]").Trim() -match "^(?i)y(es)?$") {
    if (Get-Service -Name "SysMain" -ErrorAction SilentlyContinue) {
        Stop-Service -Name "SysMain" -Force -ErrorAction Stop
        Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop
    }
} else { Write-Host "SysMain left unchanged." -ForegroundColor Gray }

Write-ProjectLog -Level INFO -Message "Optional hibernation / Fast Startup change"
Write-Host "[4/5] Optional hibernation / Fast Startup change..." -ForegroundColor Yellow
if ((Read-Host "Disable hibernation and Fast Startup? [y/N]").Trim() -match "^(?i)y(es)?$") {
    Invoke-ProjectNativeCommand -FilePath "powercfg.exe" -ArgumentList @("/hibernate", "off") | Out-Null
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power") {
        Set-ProjectRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
    }
} else { Write-Host "Hibernation left unchanged." -ForegroundColor Gray }

Write-ProjectLog -Level INFO -Message "Configuring power plan based on form factor"
Write-Host "[5/5] Configuring power plan based on form factor..." -ForegroundColor Yellow
$chassis = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
$hasBat  = $null -ne (Get-CimInstance -ClassName Win32_Battery)
if ($hasBat -or ($chassis | Where-Object { $_ -in @(8, 9, 10, 14, 30, 31, 32) })) {
    Invoke-ProjectNativeCommand -FilePath "powercfg.exe" -ArgumentList @("/setactive", "381b4222-f694-41f0-9685-ff5bb260df2e") | Out-Null
    Write-Host "      Laptop detected -> 'Balanced' power plan activated." -ForegroundColor Green
} else {
    Invoke-ProjectNativeCommand -FilePath "powercfg.exe" -ArgumentList @("/setactive", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") | Out-Null
    Write-Host "      Desktop detected -> 'High Performance' power plan activated." -ForegroundColor Green
}
if ($registrySnapshot.Count -gt 0) {
    $backupDirectory = Join-Path $PSScriptRoot "Backups\Registry"
    $backupName = "{0}-{1}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss")
    $backupPath = Join-Path $backupDirectory $backupName
    Save-ProjectRegistrySnapshot -Snapshot $registrySnapshot -Path $backupPath | Out-Null
    Write-Host "Registry backup saved: $backupPath" -ForegroundColor Cyan
}
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! System optimized and power plan adapted. ===" -ForegroundColor Green