#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Suppression complète Xbox & Game Bar (Sans Pop-up au lancement de jeu) ===" -ForegroundColor Cyan

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

# 2. Désinstallation complète de la Game Bar et des paquets Xbox (utilisateur + provisionnés)
Write-Host "[2/6] Désinstallation des paquets Appx Game Bar et Xbox..." -ForegroundColor Yellow
$xboxPackages = @(
    "Microsoft.XboxGamingOverlay",      # Xbox Game Bar principale
    "Microsoft.XboxGameOverlay",        # Overlay en jeu
    "Microsoft.XboxApp",                # Application Xbox
    "Microsoft.XboxIdentityProvider",   # Authentification Xbox
    "Microsoft.XboxSpeechToTextOverlay",# Synthèse vocale Game Bar
    "Microsoft.Xbox.TCUI",              # Interface Xbox Live
    "Microsoft.GamingApp",              # Application Xbox moderne
    "Microsoft.GamingServices"          # Services de jeux
)

foreach ($pkg in $xboxPackages) {
    Get-AppxPackage -AllUsers -Name $pkg | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $pkg } | Remove-AppxProvisionedPackage -Online | Out-Null
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

# 4. Suppression du pop-up "Vous avez besoin d'une nouvelle application pour ouvrir ce lien ms-gamebar"
Write-Host "[4/6]neutralisation des protocoles ms-gamebar et ms-gamingoverlay..." -ForegroundColor Yellow
New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" | Out-Null

$protocols = @("ms-gamebar", "ms-gamebarservices", "ms-gamingoverlay")
foreach ($proto in $protocols) {
    $protoKey = "HKCR:\$proto"
    New-Item -Path $protoKey -Force | Out-Null
    Set-ItemProperty -Path $protoKey -Name "(Default)" -Value "URL:$proto" -Type String
    Set-ItemProperty -Path $protoKey -Name "URL Protocol" -Value "" -Type String
    Set-ItemProperty -Path $protoKey -Name "NoOpenWith" -Value "" -Type String

    # Redirige l'appel système vers rundll32 sans action pour absorber silencieusement la requête sans fenêtre Windows
    $cmdKey = "$protoKey\shell\open\command"
    New-Item -Path $cmdKey -Force | Out-Null
    Set-ItemProperty -Path $cmdKey -Name "(Default)" -Value "`"$env:SystemRoot\System32\rundll32.exe`"" -Type String
}
Remove-PSDrive -Name "HKCR"

# Bloque également le déclencheur d'arrière-plan GameBarPresenceWriter.exe via IFEO
$ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GameBarPresenceWriter.exe"
New-Item -Path $ifeoPath -Force | Out-Null
Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "rundll32.exe" -Type String

# 5. Arrêt et désactivation des services Xbox en arrière-plan
Write-Host "[5/6] Désactivation des services système Xbox..." -ForegroundColor Yellow
$xboxServices = @(
    "XblAuthManager",      # Gestionnaire d'authentification Xbox Live
    "XblGameSave",         # Sauvegarde de jeu Xbox Live
    "XboxNetApiSvc",       # Service de mise en réseau Xbox Live
    "XboxGipSvc",          # Service de gestion des accessoires Xbox
    "GamingServices",      # Services de jeux
    "GamingServicesNet"    # Services réseau de jeux
)

foreach ($svc in $xboxServices) {
    if (Get-Service -Name $svc) {
        Stop-Service -Name $svc -Force
        Set-Service -Name $svc -StartupType Disabled
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -Value 4 -Type DWord
    }
}

# 6. Désactivation des tâches planifiées liées à Xbox
Write-Host "[6/6] Désactivation des tâches planifiées Xbox..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskPath -match "XblGameSave" -or $_.TaskName -match "XblGameSave|Xbox" } | Disable-ScheduledTask | Out-Null

Write-Host "`n=== Terminé ! Game Bar et services Xbox supprimés sans pop-up au lancement de jeu. ===" -ForegroundColor Green
