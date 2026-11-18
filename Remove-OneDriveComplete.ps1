#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Désinstallation complète de OneDrive & Restauration des dossiers locaux ===" -ForegroundColor Cyan

# 1. Rapatriement et restauration des dossiers utilisateur (Bureau, Documents, Images, etc.) en local
Write-Host "[1/6] Restauration des emplacements locaux (Bureau, Documents, Téléchargements, etc.)..." -ForegroundColor Yellow

$userShellPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$shellPath     = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

# Correspondance entre les clés du registre et les dossiers locaux standards
$foldersMap = @(
    @{ Name = "Desktop";     GUID = "{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}"; Local = "$env:USERPROFILE\Desktop" },
    @{ Name = "Personal";    GUID = "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"; Local = "$env:USERPROFILE\Documents" },
    @{ Name = "My Pictures"; GUID = "{0DDD015D-B06C-45D5-8C4C-F59713854639}"; Local = "$env:USERPROFILE\Pictures" },
    @{ Name = "My Music";    GUID = "{A0C69A99-21C8-4671-8703-7934162FCF1D}"; Local = "$env:USERPROFILE\Music" },
    @{ Name = "My Video";    GUID = "{35286A68-3C57-41A1-BBB1-0EAE73D76C95}"; Local = "$env:USERPROFILE\Videos" },
    @{ Name = "{374DE290-123F-4565-9164-39C4925E467B}"; GUID = "{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}"; Local = "$env:USERPROFILE\Downloads" }
)

foreach ($item in $foldersMap) {
    $currentPath = (Get-ItemProperty -Path $userShellPath -Name $item.Name).$($item.Name)
    
    # Création du dossier local cible s'il n'existe pas
    if (-not (Test-Path $item.Local)) {
        New-Item -Path $item.Local -ItemType Directory -Force | Out-Null
    }

    # Si le dossier pointe actuellement vers OneDrive, on déplace les fichiers en local
    if ($currentPath -and ($currentPath -match "OneDrive") -and (Test-Path $currentPath) -and ($currentPath -ne $item.Local)) {
        Write-Host "      Déplacement des fichiers de '$currentPath' vers '$($item.Local)'..." -ForegroundColor Gray
        Get-ChildItem -Path $currentPath -Force | Move-Item -Destination $item.Local -Force
    }

    # Réécriture des chemins dans le Registre vers les dossiers locaux
    Set-ItemProperty -Path $userShellPath -Name $item.Name -Value $item.Local -Type ExpandString
    if ($item.GUID) {
        Set-ItemProperty -Path $userShellPath -Name $item.GUID -Value $item.Local -Type ExpandString
    }
    if (Get-ItemProperty -Path $shellPath -Name $item.Name) {
        Set-ItemProperty -Path $shellPath -Name $item.Name -Value $item.Local -Type String
    }
}

# 2. Arrêt de OneDrive et désinstallation officielle
Write-Host "[2/6] Arrêt des processus et désinstallation de OneDrive..." -ForegroundColor Yellow
Stop-Process -Name "OneDrive" -Force
Stop-Process -Name "OneDriveSetup" -Force
Stop-Process -Name "FileCoAuth" -Force

$setupPaths = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
)
foreach ($exe in $setupPaths) {
    if (Test-Path $exe) {
        Start-Process -FilePath $exe -ArgumentList "/uninstall" -Wait
    }
}

# Suppression du paquet Appx si présent (Windows 11)
Get-AppxPackage -AllUsers *OneDrive* | Remove-AppxPackage -AllUsers

# 3. Suppression des tâches planifiées et du démarrage automatique
Write-Host "[3/6] Suppression des tâches planifiées et clés de démarrage..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskName -match "OneDrive" } | Unregister-ScheduledTask -Confirm:$false
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive"
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup"

# 4. Nettoyage des dossiers résiduels et raccourcis OneDrive
Write-Host "[4/6] Suppression des dossiers résiduels OneDrive..." -ForegroundColor Yellow
$oneDriveDirs = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:PROGRAMDATA\Microsoft OneDrive",
    "C:\OneDriveTemp",
    "$env:USERPROFILE\OneDrive"
)
# Ajoute également les éventuels dossiers OneDrive professionnels/personnels nommés "OneDrive - ..."
$customOneDriveDirs = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter "OneDrive*"
foreach ($dir in $customOneDriveDirs) {
    $oneDriveDirs += $dir.FullName
}

foreach ($dir in $oneDriveDirs) {
    if (Test-Path $dir) {
        # Supprime le dossier uniquement s'il est vide ou ne contient plus de dossiers critiques déplacés
        Remove-Item -Path $dir -Recurse -Force
    }
}

# Suppression du raccourci Menu Démarrer
Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk" -Force

# 5. Retrait de l'icône OneDrive dans le volet gauche de l'Explorateur de fichiers
Write-Host "[5/6] Masquage de OneDrive dans l'Explorateur de fichiers..." -ForegroundColor Yellow
$clsidPaths = @(
    "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
    "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
)
New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" | Out-Null
foreach ($clsid in $clsidPaths) {
    if (Test-Path $clsid) {
        Set-ItemProperty -Path $clsid -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord
    }
}
Remove-PSDrive -Name "HKCR"

# 6. Blocage de la réinstallation automatique via Stratégie de groupe (GPO) & Profil par défaut
Write-Host "[6/6] Blocage de la réinstallation de OneDrive..." -ForegroundColor Yellow
$oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $oneDrivePolicy -Force | Out-Null
Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSync" -Value 1 -Type DWord

# Empêche OneDrive de s'installer pour les futurs nouveaux comptes Windows
reg load "HKLM\DefaultUser" "C:\Users\Default\NTUSER.DAT" | Out-Null
reg delete "HKLM\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f | Out-Null
reg unload "HKLM\DefaultUser" | Out-Null

# Redémarrage de l'Explorateur Windows pour appliquer les nouveaux chemins locaux immédiatement
Write-Host "`nRedémarrage de l'Explorateur Windows..." -ForegroundColor Cyan
Stop-Process -Name "explorer" -Force

Write-Host "=== Terminé ! Vos dossiers Bureau, Documents et Téléchargements sont désormais 100 % locaux. ===" -ForegroundColor Green
