#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Finitions Windows (Confidentialité, Extensions, Souris 1:1 & Purge Disque) ===" -ForegroundColor Cyan

# 1. Confidentialité, Capteurs & Écran de verrouillage (Point 1)
Write-Host "[1/3] Verrouillage des permissions capteurs, diagnostics et écran de verrouillage..." -ForegroundColor Yellow

$appPrivacy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
New-Item -Path $appPrivacy -Force | Out-Null
Set-ItemProperty -Path $appPrivacy -Name "LetAppsAccessLocation" -Value 2 -Type DWord
Set-ItemProperty -Path $appPrivacy -Name "LetAppsGetDiagnosticInfo" -Value 2 -Type DWord
Set-ItemProperty -Path $appPrivacy -Name "LetAppsSyncWithDevices" -Value 2 -Type DWord

# Désactivation de la synchronisation des paramètres du compte Microsoft
$settingSync = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
New-Item -Path $settingSync -Force | Out-Null
Set-ItemProperty -Path $settingSync -Name "DisableSettingSync" -Value 2 -Type DWord
Set-ItemProperty -Path $settingSync -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord

# Désactivation de Windows Spotlight et des suggestions sur l'écran de verrouillage
$cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
New-Item -Path $cdmPath -Force | Out-Null
Set-ItemProperty -Path $cdmPath -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $cdmPath -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $cdmPath -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord

$cloudContent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
New-Item -Path $cloudContent -Force | Out-Null
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord

# 2. Extensions de fichiers, Dossiers cachés & Désactivation accélération souris (Point 2 sélectif)
Write-Host "[2/3] Affichage des extensions/fichiers cachés et désactivation de l'accélération souris..." -ForegroundColor Yellow

$advExplorer = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
New-Item -Path $advExplorer -Force | Out-Null
# HideFileExt = 0 -> Affiche toutes les extensions de fichiers (.exe, .ps1, .dll)
Set-ItemProperty -Path $advExplorer -Name "HideFileExt" -Value 0 -Type DWord
# Hidden = 1 -> Affiche les fichiers et dossiers cachés
Set-ItemProperty -Path $advExplorer -Name "Hidden" -Value 1 -Type DWord

# Désactivation de "Améliorer la précision du pointeur" (courbe souris brute 1:1)
$mousePath = "HKCU:\Control Panel\Mouse"
Set-ItemProperty -Path $mousePath -Name "MouseSpeed" -Value "0" -Type String
Set-ItemProperty -Path $mousePath -Name "MouseThreshold1" -Value "0" -Type String
Set-ItemProperty -Path $mousePath -Name "MouseThreshold2" -Value "0" -Type String

# Application immédiate des paramètres souris dans la session Windows active
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
}
"@
[MouseHelper]::SystemParametersInfo(0x0004, 0, @(0, 0, 0), 3) | Out-Null

# 3. Purge des caches temporaires, Windows Update & WinSxS (Point 3)
Write-Host "[3/3] Nettoyage des fichiers temporaires, caches Update et composants WinSxS (peut prendre 1 à 2 min)..." -ForegroundColor Yellow

# Purge %TEMP% et C:\Windows\Temp
Get-ChildItem -Path "$env:TEMP" -Force | Remove-Item -Recurse -Force
Get-ChildItem -Path "$env:SystemRoot\Temp" -Force | Remove-Item -Recurse -Force

# Arrêt temporaire des services de mise à jour pour vider les caches téléchargés
Stop-Service -Name "wuauserv" -Force
Stop-Service -Name "bits" -Force
Stop-Service -Name "dosvc" -Force

Get-ChildItem -Path "$env:SystemRoot\SoftwareDistribution\Download" -Force | Remove-Item -Recurse -Force
Get-ChildItem -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" -Force | Remove-Item -Recurse -Force

Start-Service -Name "wuauserv"

# Nettoyage des anciennes mises à jour accumulées dans WinSxS
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# Redémarrage de l'Explorateur pour actualiser l'affichage des extensions
Stop-Process -Name "explorer" -Force

Write-Host "`n=== Terminé ! Finitions appliquées et espace disque nettoyé. ===" -ForegroundColor Green
