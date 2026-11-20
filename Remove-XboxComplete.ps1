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
$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript
$registrySnapshot = @{}
$registryBackupDirectory = Join-Path $PSScriptRoot "Backups\Registry"
$registryBackupName = "{0}-{1}-{2}.json" -f [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name), (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$registryBackupFile = Join-Path $registryBackupDirectory $registryBackupName
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Removing Xbox Bloatware & Game Bar (Keeping Minecraft Auth Ready) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Stopping Xbox & Game Bar processes"
Write-Host "[1/4] Stopping Xbox & Game Bar processes..." -ForegroundColor Yellow
@("GameBar", "GameBarFTServer", "XboxApp", "XboxPcApp", "XboxGameOverlay") | ForEach-Object { Get-Process -Name "*$_*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

Write-ProjectLog -Level INFO -Message "Uninstalling Xbox apps while preserving XboxIdentityProvider"
Write-Host "[2/4] Uninstalling Xbox apps while preserving XboxIdentityProvider..." -ForegroundColor Yellow
@("Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.Xbox.TCUI") | ForEach-Object {
    $packageName = $_
    Get-AppxPackage -AllUsers -Name $packageName | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $packageName } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}

Write-ProjectLog -Level INFO -Message "Disabling Game Bar DVR, pop-ups, and ms-gamebar protocol prompts"
Write-Host "[3/4] Disabling Game Bar DVR, pop-ups, and ms-gamebar protocol prompts..." -ForegroundColor Yellow
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null
Set-ProjectRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
Set-ProjectRegistryValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
$dvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
New-Item -Path $dvrPolicy -Force | Out-Null
Set-ProjectRegistryValue -Path $dvrPolicy -Name "AllowGameDVR" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot -BackupFile $registryBackupFile
New-Item -Path "HKCU:\Software\Classes\ms-gamebar\shell\open\command" -Force | Out-Null
Set-ProjectRegistryValue -Path "HKCU:\Software\Classes\ms-gamebar" -Name "(Default)" -Value "URL:ms-gamebar" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path "HKCU:\Software\Classes\ms-gamebar" -Name "URL Protocol" -Value "" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile
Set-ProjectRegistryValue -Path "HKCU:\Software\Classes\ms-gamebar\shell\open\command" -Name "(Default)" -Value "`"$env:SystemRoot\System32\systray.exe`"" -ValueKind String -Snapshot $registrySnapshot -BackupFile $registryBackupFile

Write-ProjectLog -Level INFO -Message "Setting Xbox auth services to Manual startup for Minecraft compatibility"
Write-Host "[4/4] Setting Xbox auth services to Manual startup for Minecraft compatibility..." -ForegroundColor Yellow
@("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "GamingServices", "GamingServicesNet") | ForEach-Object {
    if (Get-Service -Name $_ -ErrorAction SilentlyContinue) { Set-Service -Name $_ -StartupType Manual -ErrorAction SilentlyContinue }
}
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Xbox bloatware removed and Game Bar pop-ups neutralized. ===" -ForegroundColor Green