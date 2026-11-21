#Requires -RunAsAdministrator
$loggingScript = Join-Path $PSScriptRoot "Common\Logging.ps1"
if (Test-Path -LiteralPath $loggingScript) {
    . $loggingScript
    Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name -LogDirectory (Join-Path $PSScriptRoot "Logs") | Out-Null
} else {
    Write-Warning "Shared logger not found at $loggingScript"
}
trap {
    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level ERROR -Message ("Unhandled terminating error: " + ($_ | Out-String).Trim())
    }
    throw
}
$safetyScript = Join-Path $PSScriptRoot "Common\Safety.ps1"
if (-not (Test-Path -LiteralPath $safetyScript)) { throw "Safety helpers not found: $safetyScript" }
. $safetyScript
$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript
$registrySnapshot = @{}
$registryBackupDirectory = Join-Path $PSScriptRoot "Backups\Registry"
$registryBackupName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$registryBackupFile = Join-Path $registryBackupDirectory $registryBackupName
$ErrorActionPreference = "SilentlyContinue"
$operationJournalScript = Join-Path $PSScriptRoot "Common\OperationJournal.ps1"
if (-not (Test-Path -LiteralPath $operationJournalScript)) { throw "Operation journal helpers not found: $operationJournalScript" }
. $operationJournalScript
$appxRecoveryScript = Join-Path $PSScriptRoot "Common\AppxRecovery.ps1"
if (-not (Test-Path -LiteralPath $appxRecoveryScript)) { throw "Appx recovery helpers not found: $appxRecoveryScript" }
. $appxRecoveryScript
$operationJournalDirectory = Join-Path $PSScriptRoot "Backups\Operations"
$operationJournalName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$operationJournalFile = Join-Path $operationJournalDirectory $operationJournalName
$appxInventoryDirectory = Join-Path $PSScriptRoot "Backups\Appx"
$appxInventoryName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$appxInventoryFile = Join-Path $appxInventoryDirectory $appxInventoryName
$installedAppxPackages = @(Get-AppxPackage -AllUsers)
$provisionedAppxPackages = @(Get-AppxProvisionedPackage -Online)
Save-ProjectAppxInventory -InstalledPackages $installedAppxPackages -ProvisionedPackages $provisionedAppxPackages -Path $appxInventoryFile | Out-Null
Write-Host "Appx inventory saved: $appxInventoryFile" -ForegroundColor Cyan
$filesystemBackupDirectory = Join-Path $PSScriptRoot "Backups\FileSystem"
Write-Host "=== Killing Processes & Full Removal (Binaries + Data/Caches) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Stopping background processes"
Write-Host "[1/5] Stopping background processes..." -ForegroundColor Yellow
@("Copilot", "Recall", "Widgets", "WidgetService", "WebExperienceHost", "Clipchamp", "olk", "HxTsr", "HxOutlook", "Cortana", "DevHome", "PhoneExperienceHost", "QuickAssist", "Microsoft.Notes", "GameBar", "Spotify") | ForEach-Object {
    Get-Process -Name "*$_*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-ProjectLog -Level INFO -Message "Disabling Windows Recall and Copilot"
Write-Host "[2/5] Disabling Windows Recall and Copilot..." -ForegroundColor Yellow
Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction SilentlyContinue | Out-Null
$aiPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; New-Item -Path $aiPolicy -Force | Out-Null
Set-ProjectRegistryValue -Path $aiPolicy -Name "DisableAIDataAnalysis" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $aiPolicy -Name "TurnOffSavingSnapshots" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$copPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; New-Item -Path $copPolicy -Force | Out-Null
Set-ProjectRegistryValue -Path $copPolicy -Name "TurnOffWindowsCopilot" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$copUser = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; New-Item -Path $copUser -Force | Out-Null
Set-ProjectRegistryValue -Path $copUser -Name "TurnOffWindowsCopilot" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$dshPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; New-Item -Path $dshPolicy -Force | Out-Null
Set-ProjectRegistryValue -Path $dshPolicy -Name "AllowNewsAndInterests" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
try {
    Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
} catch {
    Write-ProjectLog -Level WARNING -Message ("TaskbarDa is protected by Windows ACLs and could not be modified directly (Widgets already disabled via Dsh policy): " + $_.Exception.Message)
}

Write-ProjectLog -Level INFO -Message "Uninstalling bloatware apps and purging AppData folders"
Write-Host "[3/5] Uninstalling bloatware apps and purging AppData folders..." -ForegroundColor Yellow
$patterns = @("*Copilot*", "*Client.AIX*", "*Client.WebExperience*", "*Clipchamp*", "*BingNews*", "*BingSearch*", "*BingWeather*", "*GetHelp*", "*Getstarted*", "*MicrosoftOfficeHub*", "*MicrosoftSolitaireCollection*", "*MicrosoftStickyNotes*", "*OutlookForWindows*", "Microsoft.People", "*PowerAutomateDesktop*", "*Todos*", "*DevHome*", "*WindowsAlarms*", "*WindowsCommunicationsApps*", "*WindowsFeedbackHub*", "*WindowsMaps*", "*WindowsSoundRecorder*", "*YourPhone*", "*ZuneMusic*", "*ZuneVideo*", "*549981C3F5F10*", "*QuickAssist*", "*MicrosoftFamily*", "*TikTok*", "*Spotify*", "*AmazonVideo*", "*PrimeVideo*", "*Disney*", "*WhatsApp*", "*Instagram*", "*Facebook*", "*Twitter*", "*CandyCrush*", "*BubbleWitch*", "*LinkedIn*", "*AdobeExpress*", "*Dropbox*")
foreach ($p in $patterns) {
    Get-AppxPackage -AllUsers -Name $p | Where-Object { $_.NonRemovable -eq $false -and $_.InstallLocation -notlike "*\SystemApps\*" } | ForEach-Object {
        Invoke-ProjectAppxPackageRemoval -Package $_ -PackageType Installed -JournalPath $operationJournalFile | Out-Null
    }
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $p } | ForEach-Object {
        Invoke-ProjectAppxPackageRemoval -Package $_ -PackageType Provisioned -JournalPath $operationJournalFile | Out-Null
    }
    Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Directory -Filter $p -ErrorAction SilentlyContinue | ForEach-Object { Remove-ProjectPackageDirectory -TargetPath $_.FullName -PackagesRoot (Join-Path $env:LOCALAPPDATA "Packages") -BackupDirectory $filesystemBackupDirectory | Out-Null }
}

Write-ProjectLog -Level INFO -Message "Skipping broad residual-folder deletion"
Write-Host "[4/5] Skipping broad residual-folder deletion..." -ForegroundColor Yellow
Write-Host "Only app data directories directly under $env:LOCALAPPDATA\\Packages are eligible for removal." -ForegroundColor DarkYellow

Write-ProjectLog -Level INFO -Message "Blocking sponsored suggestions"
Write-Host "[5/5] Blocking sponsored suggestions..." -ForegroundColor Yellow
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; New-Item -Path $cdm -Force | Out-Null
@("ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SystemPaneSuggestionsEnabled") | ForEach-Object {
    try {
        Set-ProjectRegistryValue -Path $cdm -Name $_ -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
    } catch {
        Write-ProjectLog -Level WARNING -Message ("Could not set ContentDeliveryManager\$_ : " + $_.Exception.Message)
    }
}
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; New-Item -Path $cc -Force | Out-Null
Set-ProjectRegistryValue -Path $cc -Name "DisableWindowsConsumerFeatures" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path $cc -Name "DisableSoftLanding" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
try {
    Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
} catch {
    Write-ProjectLog -Level WARNING -Message ("Could not set Start_IrisRecommendations: " + $_.Exception.Message)
}
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Bloatware removed and sponsored suggestions blocked. ===" -ForegroundColor Green