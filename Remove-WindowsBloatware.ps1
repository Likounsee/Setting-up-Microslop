#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Killing Processes & Full Removal (Binaries + Data/Caches) ===" -ForegroundColor Cyan

function Remove-FolderForce([string]$TargetPath) {
    if (Test-Path $TargetPath) {
        # Do not take ownership or rewrite ACLs; remove only the targeted cache folder.
        Remove-Item -Path $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[1/5] Stopping background processes..." -ForegroundColor Yellow
@("Copilot", "Recall", "Widgets", "WidgetService", "WebExperienceHost", "Clipchamp", "olk", "HxTsr", "HxOutlook", "Cortana", "DevHome", "PhoneExperienceHost", "QuickAssist", "Microsoft.Notes", "GameBar", "Spotify") | ForEach-Object {
    Get-Process -Name "*$_*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "[2/5] Disabling Windows Recall and Copilot..." -ForegroundColor Yellow
Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction SilentlyContinue | Out-Null
$aiPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; New-Item -Path $aiPolicy -Force | Out-Null
Set-ItemProperty -Path $aiPolicy -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
Set-ItemProperty -Path $aiPolicy -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord
$copPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; New-Item -Path $copPolicy -Force | Out-Null
Set-ItemProperty -Path $copPolicy -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
$copUser = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; New-Item -Path $copUser -Force | Out-Null
Set-ItemProperty -Path $copUser -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord
$dshPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; New-Item -Path $dshPolicy -Force | Out-Null
Set-ItemProperty -Path $dshPolicy -Name "AllowNewsAndInterests" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord

Write-Host "[3/5] Uninstalling bloatware apps and purging AppData folders..." -ForegroundColor Yellow
$patterns = @("*Copilot*", "*Client.AIX*", "*Client.WebExperience*", "*Clipchamp*", "*BingNews*", "*BingSearch*", "*BingWeather*", "*GetHelp*", "*Getstarted*", "*MicrosoftOfficeHub*", "*MicrosoftSolitaireCollection*", "*MicrosoftStickyNotes*", "*OutlookForWindows*", "Microsoft.People", "*PowerAutomateDesktop*", "*Todos*", "*DevHome*", "*WindowsAlarms*", "*WindowsCommunicationsApps*", "*WindowsFeedbackHub*", "*WindowsMaps*", "*WindowsSoundRecorder*", "*YourPhone*", "*ZuneMusic*", "*ZuneVideo*", "*549981C3F5F10*", "*QuickAssist*", "*MicrosoftFamily*", "*TikTok*", "*Spotify*", "*AmazonVideo*", "*PrimeVideo*", "*Disney*", "*WhatsApp*", "*Instagram*", "*Facebook*", "*Twitter*", "*CandyCrush*", "*BubbleWitch*", "*LinkedIn*", "*AdobeExpress*", "*Dropbox*")
foreach ($p in $patterns) {
    Get-AppxPackage -AllUsers -Name $p | Where-Object { $_.NonRemovable -eq $false -and $_.InstallLocation -notlike "*\SystemApps\*" } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $p } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
    Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Directory -Filter $p -ErrorAction SilentlyContinue | ForEach-Object { Remove-FolderForce $_.FullName }
}

Write-Host "[4/5] Cleaning residual system directories..." -ForegroundColor Yellow
@("$env:LOCALAPPDATA\Microsoft\Windows\Recall", "$env:LOCALAPPDATA\Microsoft\Olk", "$env:LOCALAPPDATA\Microsoft\OneAuth", "$env:LOCALAPPDATA\Microsoft\IdentityCache", "$env:LOCALAPPDATA\Microsoft\Copilot", "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy", "$env:LOCALAPPDATA\Packages\Microsoft.Copilot_8wekyb3d8bbwe") | ForEach-Object {
    Get-Item -Path $_ -ErrorAction SilentlyContinue | ForEach-Object { Remove-FolderForce $_.FullName }
}

Write-Host "[5/5] Blocking sponsored suggestions..." -ForegroundColor Yellow
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; New-Item -Path $cdm -Force | Out-Null
@("ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SystemPaneSuggestionsEnabled") | ForEach-Object {
    Set-ItemProperty -Path $cdm -Name $_ -Value 0 -Type DWord
}
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; New-Item -Path $cc -Force | Out-Null
Set-ItemProperty -Path $cc -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path $cc -Name "DisableSoftLanding" -Value 1 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0 -Type DWord
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Write-Host "`n=== Done! Processes stopped, apps uninstalled, and data folders purged. ===" -ForegroundColor Green