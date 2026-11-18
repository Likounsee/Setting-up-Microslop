#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Suppression complète de Microsoft Edge & Réinstallation WebView2 ===" -ForegroundColor Cyan

# 1. Arrêt de tous les processus et services Edge / WebView2
Write-Host "[1/6] Arrêt des processus et services Edge..." -ForegroundColor Yellow
$processes = @("msedge", "msedgewebview2", "MicrosoftEdgeUpdate", "edge", "pwahelper", "identity_helper")
foreach ($proc in $processes) {
    Get-Process -Name $proc | Stop-Process -Force
}

$services = @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")
foreach ($svc in $services) {
    Stop-Service -Name $svc -Force
    sc.exe delete $svc | Out-Null
}

# 2. Suppression des tâches planifiées liées à Edge
Write-Host "[2/6] Suppression des tâches planifiées Edge..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskName -match "MicrosoftEdge" } | Unregister-ScheduledTask -Confirm:$false

# 3. Désinstallation officielle via le setup interne d'Edge (avec déverrouillage temporaire)
Write-Host "[3/6] Exécution du désinstalleur officiel Microsoft Edge..." -ForegroundColor Yellow
$edgeRegPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
)
foreach ($path in $edgeRegPaths) {
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name "NoRemove"
    }
}

$setupExes = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe"
foreach ($exe in $setupExes) {
    Start-Process -FilePath $exe.FullName -ArgumentList "--uninstall --system-level --verbose-logging --force-uninstall" -Wait
}

# Désinstallation des paquets Appx Edge (hors WebView2)
Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "Microsoft.MicrosoftEdge" -and $_.Name -notmatch "WebView" } | Remove-AppxPackage -AllUsers

# 4. Nettoyage complet des dossiers résiduels et raccourcis Edge
Write-Host "[4/6] Suppression des fichiers et raccourcis résiduels..." -ForegroundColor Yellow
$foldersToDelete = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate",
    "${env:ProgramFiles(x86)}\Microsoft\Temp",
    "$env:ProgramFiles\Microsoft\Edge",
    "$env:ProgramFiles\Microsoft\EdgeCore",
    "$env:ProgramFiles\Microsoft\EdgeUpdate",
    "$env:LOCALAPPDATA\Microsoft\Edge"
)
foreach ($folder in $foldersToDelete) {
    if (Test-Path $folder) {
        Remove-Item -Path $folder -Recurse -Force
    }
}

# Suppression des raccourcis Bureau et Menu Démarrer
$shortcuts = @(
    "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
    "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
)
foreach ($lnk in $shortcuts) {
    if (Test-Path $lnk) { Remove-Item -Path $lnk -Force }
}

# 5. Blocage de la réinstallation automatique du navigateur Edge via le Registre
Write-Host "[5/6] Blocage de la réinstallation automatique de Edge..." -ForegroundColor Yellow
$edgeUpdatePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
New-Item -Path $edgeUpdatePolicy -Force | Out-Null

# Bloque uniquement le navigateur Edge (GUID {56EB18F8-B008-4CBD-B6D2-8C97FE7E9062})
Set-ItemProperty -Path $edgeUpdatePolicy -Name "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -Type DWord
Set-ItemProperty -Path $edgeUpdatePolicy -Name "Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -Type DWord
Set-ItemProperty -Path $edgeUpdatePolicy -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord

# Empêche Windows Update de réinstaller Edge
New-Item -Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate" -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord

# 6. Réinstallation propre de WebView2 Runtime avec mises à jour activées
Write-Host "[6/6] Téléchargement et installation de Microsoft Edge WebView2 Runtime..." -ForegroundColor Yellow
$ErrorActionPreference = "Stop"
$wv2Installer = "$env:TEMP\MicrosoftEdgeWebview2Setup.exe"
$wv2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

try {
    Invoke-WebRequest -Uri $wv2Url -OutFile $wv2Installer -UseBasicParsing
    Start-Process -FilePath $wv2Installer -ArgumentList "/silent /install" -Wait

    # Activation explicite des mises à jour automatiques uniquement pour WebView2 (GUID {F3017226-FE2A-4295-8BDF-00C3A9A7E4C5})
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -Value 1 -Type DWord
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -Value 1 -Type DWord
    Set-ItemProperty -Path $edgeUpdatePolicy -Name "AutoUpdateCheckPeriodMinutes" -Value 1400 -Type DWord
}
finally {
    if (Test-Path $wv2Installer) {
        Remove-Item -Path $wv2Installer -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Terminé ! ===" -ForegroundColor Cyan
Write-Host " - Navigateur Edge : Supprimé et bloqué." -ForegroundColor Green
Write-Host " - WebView2 Runtime : Installé et mises à jour activées." -ForegroundColor Green
