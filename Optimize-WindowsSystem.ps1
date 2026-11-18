#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Optimisation Système (Télémétrie, P2P, SysMain, Hibernation & Profil d'alimentation adaptatif) ===" -ForegroundColor Cyan

# 1. Désactivation complète de la Télémétrie & Collecte de données (DiagTrack / CompatTelRunner)
Write-Host "[1/5] Désactivation de la télémétrie et des tâches de diagnostic..." -ForegroundColor Yellow

$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($svc in $telemetryServices) {
    if (Get-Service -Name $svc) {
        Stop-Service -Name $svc -Force
        Set-Service -Name $svc -StartupType Disabled
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -Value 4 -Type DWord
    }
}

$dataCollection = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
New-Item -Path $dataCollection -Force | Out-Null
Set-ItemProperty -Path $dataCollection -Name "AllowTelemetry" -Value 0 -Type DWord
Set-ItemProperty -Path $dataCollection -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
Set-ItemProperty -Path $dataCollection -Name "DisableOneSettingsDownloads" -Value 1 -Type DWord

# Désactivation de l'identifiant publicitaire et du suivi des lancements d'applications
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord

New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -Type DWord

# Désactivation de l'historique d'activité (Timeline)
$systemPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
New-Item -Path $systemPolicy -Force | Out-Null
Set-ItemProperty -Path $systemPolicy -Name "EnableActivityFeed" -Value 0 -Type DWord
Set-ItemProperty -Path $systemPolicy -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path $systemPolicy -Name "UploadUserActivities" -Value 0 -Type DWord

# Désactivation des tâches planifiées de télémétrie
$telemetryTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
)
foreach ($task in $telemetryTasks) {
    schtasks /Change /TN "$task" /DISABLE | Out-Null
}

# 2. Désactivation du partage P2P Windows Update (Optimisation de livraison)
Write-Host "[2/5] Désactivation du P2P Windows Update (Delivery Optimization)..." -ForegroundColor Yellow

$doPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
New-Item -Path $doPolicy -Force | Out-Null
Set-ItemProperty -Path $doPolicy -Name "DODownloadMode" -Value 0 -Type DWord

$doConfig = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
New-Item -Path $doConfig -Force | Out-Null
Set-ItemProperty -Path $doConfig -Name "DODownloadMode" -Value 0 -Type DWord

# 3. Désactivation du préchargement mémoire SysMain (Superfetch) & Applications en arrière-plan
Write-Host "[3/5] Arrêt et désactivation de SysMain (préchargement) & apps en arrière-plan..." -ForegroundColor Yellow

if (Get-Service -Name "SysMain") {
    Stop-Service -Name "SysMain" -Force
    Set-Service -Name "SysMain" -StartupType Disabled
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain" -Name "Start" -Value 4 -Type DWord
}

$bgAppsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
New-Item -Path $bgAppsPolicy -Force | Out-Null
Set-ItemProperty -Path $bgAppsPolicy -Name "LetAppsRunInBackground" -Value 2 -Type DWord

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type DWord

# 4. Suppression de l'Hibernation (libère hiberfil.sys) et du Démarrage rapide
Write-Host "[4/5] Suppression de l'hibernation (hiberfil.sys) et du Démarrage rapide..." -ForegroundColor Yellow

powercfg.exe /hibernate off

$powerSession = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
if (Test-Path $powerSession) {
    Set-ItemProperty -Path $powerSession -Name "HiberbootEnabled" -Value 0 -Type DWord
}

# 5. Détection automatique Portable vs Fixe pour le profil d'alimentation
Write-Host "[5/5] Configuration du profil d'alimentation selon le type de PC..." -ForegroundColor Yellow

$chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
$hasBattery   = $null -ne (Get-CimInstance -ClassName Win32_Battery)
# Types de châssis portables : 8 (Portable), 9 (Laptop), 10 (Notebook), 14 (Sub Notebook), 30 (Tablet), 31 (Convertible), 32 (Detachable)
$isLaptop     = $hasBattery -or ($chassisTypes | Where-Object { $_ -in @(8, 9, 10, 14, 30, 31, 32) })

if ($isLaptop) {
    # Utilisation normale (Balanced) : gestion dynamique de la fréquence CPU
    powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null
    Write-Host "      PC Portable détecté -> Mode 'Utilisation normale' (fréquence CPU dynamique) activé." -ForegroundColor Green
} else {
    # Performances élevées : fréquence CPU maximale sur PC fixe
    powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
    Write-Host "      PC Fixe détecté -> Mode 'Performances élevées' activé." -ForegroundColor Green
}

Write-Host "`n=== Terminé ! Système optimisé et profil d'alimentation adapté à votre machine. ===" -ForegroundColor Green
