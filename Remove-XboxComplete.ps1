#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Removing Xbox Bloatware & Game Bar (Keeping Minecraft Auth Ready) ===" -ForegroundColor Cyan

Write-Host "[1/4] Stopping Xbox & Game Bar processes..." -ForegroundColor Yellow
@("GameBar", "GameBarFTServer", "XboxApp", "XboxPcApp", "XboxGameOverlay") | ForEach-Object { Get-Process -Name "*$_*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

Write-Host "[2/4] Uninstalling Xbox apps while preserving XboxIdentityProvider..." -ForegroundColor Yellow
@("Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.Xbox.TCUI") | ForEach-Object {
    Get-AppxPackage -AllUsers -Name $_ | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $_ } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "[3/4] Disabling Game Bar DVR, pop-ups, and ms-gamebar protocol prompts..." -ForegroundColor Yellow
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord
New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
$dvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
New-Item -Path $dvrPolicy -Force | Out-Null
Set-ItemProperty -Path $dvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord
New-Item -Path "HKCU:\Software\Classes\ms-gamebar\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\ms-gamebar" -Name "(Default)" -Value "URL:ms-gamebar" -Type String
Set-ItemProperty -Path "HKCU:\Software\Classes\ms-gamebar" -Name "URL Protocol" -Value "" -Type String
Set-ItemProperty -Path "HKCU:\Software\Classes\ms-gamebar\shell\open\command" -Name "(Default)" -Value "`"$env:SystemRoot\System32\systray.exe`"" -Type String

Write-Host "[4/4] Setting Xbox auth services to Manual startup for Minecraft compatibility..." -ForegroundColor Yellow
@("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "GamingServices", "GamingServicesNet") | ForEach-Object {
    if (Get-Service -Name $_ -ErrorAction SilentlyContinue) { Set-Service -Name $_ -StartupType Manual -ErrorAction SilentlyContinue }
}
Write-Host "`n=== Done! Xbox bloatware removed and Game Bar pop-ups neutralized. ===" -ForegroundColor Green