#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Arrêt des processus & Suppression complète (Binaires + Données/Caches) ===" -ForegroundColor Cyan

# Fonction utilitaire pour forcer la suppression d'un dossier même verrouillé par TrustedInstaller
function Remove-FolderForce {
    param([string]$TargetPath)
    if (Test-Path $TargetPath) {
        takeown /F "$TargetPath" /R /D O | Out-Null
        icacls "$TargetPath" /grantAdministrators:F /T /C /Q | Out-Null
        icacls "$TargetPath" /grant *S-1-5-32-544:F /T /C /Q | Out-Null
        Remove-Item -Path $TargetPath -Recurse -Force
    }
}

# 1. Arrêt forcé de tous les processus liés aux applications ciblées
Write-Host "[1/5] Arrêt des processus et tâches d'arrière-plan..." -ForegroundColor Yellow
$processesToKill = @(
    "Copilot",
    "ai",
    "Recall",
    "Widgets",
    "WidgetService",
    "WebExperienceHost",
    "Clipchamp",
    "olk",                  # Nouvel Outlook
    "HxTsr",                # Courrier / Calendrier
    "HxOutlook",
    "Cortana",
    "SearchHost",
    "DevHome",
    "PhoneExperienceHost",
    "QuickAssist",
    "Microsoft.Notes",      # Sticky Notes
    "GameBar",
    "Spotify"
)

foreach ($proc in $processesToKill) {
    Get-Process -Name "*$proc*" | Stop-Process -Force
}

# 2. Désactivation de Windows Recall & Copilot (DISM + Stratégies)
Write-Host "[2/5] Désactivation de Windows Recall et Copilot..." -ForegroundColor Yellow
Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart | Out-Null

$aiPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
New-Item -Path $aiPolicy -Force | Out-Null
Set-ItemProperty -Path $aiPolicy -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
Set-ItemProperty -Path $aiPolicy -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord

$copilotPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
New-Item -Path $copilotPolicy -Force | Out-Null
Set-ItemProperty -Path $copilotPolicy -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord

$copilotUserPolicy = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
New-Item -Path $copilotUserPolicy -Force | Out-Null
Set-ItemProperty -Path $copilotUserPolicy -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord

$dshPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
New-Item -Path $dshPolicy -Force | Out-Null
Set-ItemProperty -Path $dshPolicy -Name "AllowNewsAndInterests" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord

# 3. Désinstallation des paquets Appx et suppression intégrale de leurs dossiers AppData / Caches
Write-Host "[3/5] Désinstallation des applications et purge de leurs dossiers de données..." -ForegroundColor Yellow

$targetPatterns = @(
    "*Copilot*",
    "*Client.AIX*",
    "*Client.WebExperience*",
    "*Clipchamp*",
    "*BingNews*",
    "*BingSearch*",
    "*BingWeather*",
    "*GetHelp*",
    "*Getstarted*",
    "*MicrosoftOfficeHub*",
    "*MicrosoftSolitaireCollection*",
    "*MicrosoftStickyNotes*",
    "*OutlookForWindows*",
    "*People*",
    "*PowerAutomateDesktop*",
    "*Todos*",
    "*DevHome*",
    "*WindowsAlarms*",
    "*WindowsCommunicationsApps*",
    "*WindowsFeedbackHub*",
    "*WindowsMaps*",
    "*WindowsSoundRecorder*",
    "*YourPhone*",
    "*ZuneMusic*",
    "*ZuneVideo*",
    "*549981C3F5F10*", # Cortana
    "*QuickAssist*",
    "*MicrosoftFamily*",
    "*TikTok*",
    "*Spotify*",
    "*AmazonVideo*",
    "*PrimeVideo*",
    "*Disney*",
    "*WhatsApp*",
    "*Instagram*",
    "*Facebook*",
    "*Twitter*",
    "*CandyCrush*",
    "*BubbleWitch*",
    "*LinkedIn*",
    "*AdobeExpress*",
    "*Dropbox*"
)

foreach ($pattern in $targetPatterns) {
    # Désinstallation du paquet pour tous les utilisateurs + provisionnement
    Get-AppxPackage -AllUsers -Name $pattern | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pattern } | Remove-AppxProvisionedPackage -Online | Out-Null

    # Suppression des dossiers de données locaux (%LOCALAPPDATA%\Packages\<NomPaquet_...>)
    Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Directory -Filter $pattern | ForEach-Object {
        Write-Host "      Suppression des données : $($_.Name)" -ForegroundColor Gray
        Remove-FolderForce -TargetPath $_.FullName
    }

    # Suppression des éventuels dossiers résiduels dans WindowsApps (si non verrouillés)
    Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Directory -Filter $pattern | ForEach-Object {
        Remove-FolderForce -TargetPath $_.FullName
    }
}

# 4. Nettoyage des répertoires de cache et données spécifiques hors Packages (Recall, Copilot, Olk, Widgets)
Write-Host "[4/5] Nettoyage des dossiers système résiduels (Recall, Copilot, Outlook, Widgets)..." -ForegroundColor Yellow
$extraDataFolders = @(
    "$env:LOCALAPPDATA\Microsoft\Windows\Recall",
    "$env:LOCALAPPDATA\Microsoft\Olk",
    "$env:LOCALAPPDATA\Microsoft\OneAuth",
    "$env:LOCALAPPDATA\Microsoft\IdentityCache",
    "$env:LOCALAPPDATA\Microsoft\Copilot",
    "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy",
    "$env:LOCALAPPDATA\Packages\Microsoft.Copilot_8wekyb3d8bbwe",
    "$env:PROGRAMDATA\Microsoft\Windows\AppRepository\Packages\*Copilot*",
    "$env:PROGRAMDATA\Microsoft\Windows\AppRepository\Packages\*WebExperience*"
)

foreach ($folder in $extraDataFolders) {
    Get-Item -Path $folder | ForEach-Object {
        Remove-FolderForce -TargetPath $_.FullName
    }
}

# 5. Blocage des téléchargements et suggestions sponsorisées (ContentDeliveryManager)
Write-Host "[5/5] Blocage définitif des suggestions et téléchargements automatiques..." -ForegroundColor Yellow
$cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
New-Item -Path $cdmPath -Force | Out-Null

$cdmKeys = @(
    "ContentDeliveryAllowed",
    "FeatureManagementEnabled",
    "OemPreInstalledAppsEnabled",
    "PreInstalledAppsEnabled",
    "PreInstalledAppsEverEnabled",
    "SilentInstalledAppsEnabled",
    "SoftLandingEnabled",
    "SubscribedContent-310093Enabled",
    "SubscribedContent-338387Enabled",
    "SubscribedContent-338388Enabled",
    "SubscribedContent-338389Enabled",
    "SubscribedContent-338393Enabled",
    "SubscribedContent-353694Enabled",
    "SubscribedContent-353696Enabled",
    "SystemPaneSuggestionsEnabled"
)

foreach ($key in $cdmKeys) {
    Set-ItemProperty -Path $cdmPath -Name $key -Value 0 -Type DWord
}

$cloudContent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
New-Item -Path $cloudContent -Force | Out-Null
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableSoftLanding" -Value 1 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0 -Type DWord

# Redémarrage de l'Explorateur pour libérer les handles résiduels
Stop-Process -Name "explorer" -Force

Write-Host "`n=== Terminé ! Processus arrêtés, applications désinstallées et dossiers de données purgés. ===" -ForegroundColor Green
