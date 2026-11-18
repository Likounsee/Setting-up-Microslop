#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Suppression Xbox & Game Bar (Compatible réinstallation à la demande Minecraft) ===" -ForegroundColor Cyan

# 1. Arrêt de tous les processus Xbox et Game Bar actifs
Write-Host "[1/6] Arrêt des processus Xbox et Game Bar..." -ForegroundColor Yellow
$xboxProcesses = @(
    "GameBar",
    "GameBarFTServer",
    "GameBarPresenceWriter",
    "XboxApp",
    "XboxPcApp",
    "XboxPcAppFT",
    "XboxPcTray",
    "XboxGameBarWidgets"
)
foreach ($proc in $xboxProcesses) {
    Get-Process -Name $proc | Stop-Process -Force
}

# 2. Désinstallation de la Game Bar et des apps Xbox (sans bloquer le Store pour Minecraft)
Write-Host "[2/6] Désinstallation des paquets Appx Game Bar et Xbox..." -ForegroundColor Yellow
$bloatXboxPackages = @(
    "Microsoft.XboxGamingOverlay",       # Xbox Game Bar principale
    "Microsoft.XboxGameOverlay",         # Overlay en jeu
    "Microsoft.XboxApp",                 # Ancienne app Xbox
    "Microsoft.XboxSpeechToTextOverlay", # Synthèse vocale Game Bar
    "Microsoft.Xbox.TCUI",               # Interface Xbox Live
    "Microsoft.GamingApp"                # App Xbox moderne
)

# Suppression définitive (utilisateur + provisionné) pour la Game Bar et l'interface Xbox
foreach ($pkg in $bloatXboxPackages) {
    Get-AppxPackage -AllUsers -Name $pkg | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $pkg } | Remove-AppxProvisionedPackage -Online | Out-Null
}

# Suppression simple (sans toucher au provisionnement) pour l'auth Minecraft : réinstallable à la demande
$onDemandPackages = @(
    "Microsoft.XboxIdentityProvider",
    "Microsoft.GamingServices"
)
foreach ($pkg in $onDemandPackages) {
    Get-AppxPackage -AllUsers -Name $pkg | Remove-AppxPackage -AllUsers
}

# 3. Désactivation de la Game Bar, du Game DVR et du bouton Guide manette
Write-Host "[3/6] Désactivation de la Game Bar et du Game DVR..." -ForegroundColor Yellow
$gameBarPath = "HKCU:\Software\Microsoft\GameBar"
New-Item -Path $gameBarPath -Force | Out-Null
Set-ItemProperty -Path $gameBarPath -Name "AllowAutoGameMode" -Value 0 -Type DWord
Set-ItemProperty -Path $gameBarPath -Name "AutoGameModeEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $gameBarPath -Name "ShowStartupPanel" -Value 0 -Type DWord
Set-ItemProperty -Path $gameBarPath -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord

$gameDvrUser = "HKCU:\System\GameConfigStore"
New-Item -Path $gameDvrUser -Force | Out-Null
Set-ItemProperty -Path $gameDvrUser -Name "GameDVR_Enabled" -Value 0 -Type DWord
Set-ItemProperty -Path $gameDvrUser -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord
Set-ItemProperty -Path $gameDvrUser -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord
Set-ItemProperty -Path $gameDvrUser -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord

$gameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
New-Item -Path $gameDvrPolicy -Force | Out-Null
Set-ItemProperty -Path $gameDvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord

New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord

# 4. Neutralisation du pop-up "Vous avez besoin d'une nouvelle application pour ouvrir ce lien ms-gamebar"
Write-Host "[4/6] Neutralisation des protocoles ms-gamebar et ms-gamingoverlay..." -ForegroundColor Yellow
New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" | Out-Null

$protocols = @("ms-gamebar", "ms-gamebarservices", "ms-gamingoverlay")
foreach ($proto in $protocols) {
    $protoKey = "HKCR:\$proto"
    New-Item -Path $protoKey -Force | Out-Null
    Set-ItemProperty -Path $protoKey -Name "(Default)" -Value "URL:$proto" -Type String
    Set-ItemProperty -Path $protoKey -Name "URL Protocol" -Value "" -Type String
    Set-ItemProperty -Path $protoKey -Name "NoOpenWith" -Value "" -Type String

    $cmdKey = "$protoKey\shell\open\command"
    New-Item -Path $cmdKey -Force | Out-Null
    Set-ItemProperty -Path $cmdKey -Name "(Default)" -Value "`"$env:SystemRoot\System32\rundll32.exe`"" -Type String
}
Remove-PSDrive -Name "HKCR"

$ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GameBarPresenceWriter.exe"
New-Item -Path $ifeoPath -Force | Out-Null
Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "rundll32.exe" -Type String

# 5. Arrêt des services Xbox et passage en démarrage Manuel (0 RAM au repos, réactivable par Minecraft)
Write-Host "[5/6] Passage des services Xbox en mode Manuel (arrêtés au repos)..." -ForegroundColor Yellow
$xboxServices = @(
    "XblAuthManager",      # Authentification Xbox Live (requis par Minecraft)
    "XblGameSave",         # Sauvegarde Xbox Live
    "XboxNetApiSvc",       # Réseau Xbox Live
    "XboxGipSvc",          # Accessoires Xbox
    "GamingServices",      # Services de jeux
    "GamingServicesNet"    # Services réseau de jeux
)

foreach ($svc in $xboxServices) {
    if (Get-Service -Name $svc) {
        Stop-Service -Name $svc -Force
        Set-Service -Name $svc -StartupType Manual
        # Valeur 3 = Manual (Démarrage à la demande uniquement)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -Value 3 -Type DWord
    }
}

# 6. Désactivation des tâches planifiées de télémétrie/sauvegarde en arrière-plan
Write-Host "[6/6] Désactivation des tâches planifiées Xbox..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskPath -match "XblGameSave" -or $_.TaskName -match "XblGameSave|Xbox" } | Disable-ScheduledTask | Out-Null

Write-Host "`n=== Terminé ! Game Bar supprimée sans pop-up, services Xbox arrêtés (réinstallables si besoin). ===" -ForegroundColor Green
