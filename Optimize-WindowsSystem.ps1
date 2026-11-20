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
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== System Optimization (Telemetry, P2P, SysMain, Hibernation & Adaptive Power) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Disabling telemetry and diagnostic tasks"
Write-Host "[1/5] Disabling telemetry and diagnostic tasks..." -ForegroundColor Yellow
@("DiagTrack", "dmwappushservice") | ForEach-Object {
    if (Get-Service -Name $_ -ErrorAction SilentlyContinue) {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$_" -Name "Start" -Value 4 -Type DWord
    }
}
$dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; New-Item -Path $dc -Force | Out-Null
Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value 0 -Type DWord
Set-ItemProperty -Path $dc -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
Set-ItemProperty -Path $dc -Name "DisableOneSettingsDownloads" -Value 1 -Type DWord
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -Type DWord
$sp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; New-Item -Path $sp -Force | Out-Null
Set-ItemProperty -Path $sp -Name "EnableActivityFeed" -Value 0 -Type DWord
Set-ItemProperty -Path $sp -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path $sp -Name "UploadUserActivities" -Value 0 -Type DWord
@("\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser", "\Microsoft\Windows\Application Experience\ProgramDataUpdater", "\Microsoft\Windows\Application Experience\StartupAppTask", "\Microsoft\Windows\Autochk\Proxy", "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator", "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip", "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector", "\Microsoft\Windows\Feedback\Siuf\DmClient", "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload") | ForEach-Object {
    schtasks /Change /TN "$_" /DISABLE 2>$null | Out-Null
}

Write-ProjectLog -Level INFO -Message "Disabling Windows Update P2P"
Write-Host "[2/5] Disabling Windows Update P2P..." -ForegroundColor Yellow
$do1 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; New-Item -Path $do1 -Force | Out-Null
Set-ItemProperty -Path $do1 -Name "DODownloadMode" -Value 0 -Type DWord
$do2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"; New-Item -Path $do2 -Force | Out-Null
Set-ItemProperty -Path $do2 -Name "DODownloadMode" -Value 0 -Type DWord

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
    powercfg.exe /hibernate off
    if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate off failed with exit code $LASTEXITCODE" }
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power") {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord
    }
} else { Write-Host "Hibernation left unchanged." -ForegroundColor Gray }

Write-ProjectLog -Level INFO -Message "Configuring power plan based on form factor"
Write-Host "[5/5] Configuring power plan based on form factor..." -ForegroundColor Yellow
$chassis = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
$hasBat  = $null -ne (Get-CimInstance -ClassName Win32_Battery)
if ($hasBat -or ($chassis | Where-Object { $_ -in @(8, 9, 10, 14, 30, 31, 32) })) {
    powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null
    Write-Host "      Laptop detected -> 'Balanced' power plan activated." -ForegroundColor Green
} else {
    powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
    Write-Host "      Desktop detected -> 'High Performance' power plan activated." -ForegroundColor Green
}
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! System optimized and power plan adapted. ===" -ForegroundColor Green