#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Complete OneDrive Removal & Local Folder Restoration ===" -ForegroundColor Cyan

Write-Host "[1/4] Stopping OneDrive processes..." -ForegroundColor Yellow
@("OneDrive", "OneDriveSetup", "FileCoAuth") | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

Write-Host "[2/4] Uninstalling OneDrive..." -ForegroundColor Yellow
@("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | ForEach-Object {
    if (Test-Path $_) { Start-Process -FilePath $_ -ArgumentList "/uninstall" -Wait }
}

Write-Host "[3/4] Restoring Desktop, Documents, Pictures, Music & Videos locally..." -ForegroundColor Yellow
$shellKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
@{ "Desktop" = "$env:USERPROFILE\Desktop"; "Personal" = "$env:USERPROFILE\Documents"; "My Pictures" = "$env:USERPROFILE\Pictures"; "My Music" = "$env:USERPROFILE\Music"; "My Video" = "$env:USERPROFILE\Videos" }.GetEnumerator() | ForEach-Object {
    if (-not (Test-Path $_.Value)) { New-Item -Path $_.Value -ItemType Directory -Force | Out-Null }
    Set-ItemProperty -Path $shellKey -Name $_.Key -Value $_.Value -Type ExpandString
}

Write-Host "[4/4] Cleaning residual OneDrive folders and blocking reinstallation..." -ForegroundColor Yellow
Write-Warning "The user OneDrive folder is intentionally preserved to protect synced and online-only files."
@("$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:PROGRAMDATA\Microsoft OneDrive", "C:\OneDriveTemp") | ForEach-Object {
    if (Test-Path $_) { Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue }
}
if (Test-Path "$env:USERPROFILE\OneDrive") {
    Write-Warning "Review and manually migrate files from $env:USERPROFILE\OneDrive before deleting it. Files On-Demand may exist only in the cloud."
}
$odPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $odPolicy -Force | Out-Null
Set-ItemProperty -Path $odPolicy -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
Remove-Item -Path "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Recurse -Force -ErrorAction SilentlyContinue
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Write-Host "`n=== Done! OneDrive uninstalled and local user directories restored. ===" -ForegroundColor Green