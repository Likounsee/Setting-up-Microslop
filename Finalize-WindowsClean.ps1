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
$serviceStateScript = Join-Path $PSScriptRoot "Common\ServiceState.ps1"
if (-not (Test-Path -LiteralPath $serviceStateScript)) { throw "Service-state helpers not found: $serviceStateScript" }
. $serviceStateScript
$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) { throw "Registry helpers not found: $registryScript" }
. $registryScript
$registrySnapshot = @{}
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Final Tweaks (Privacy, File Extensions, 1:1 Mouse & Disk Cleanup) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Locking down sensor permissions, diagnostics, and lock screen Spotlight"
Write-Host "[1/3] Locking down sensor permissions, diagnostics, and lock screen Spotlight..." -ForegroundColor Yellow
$ap = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; New-Item -Path $ap -Force | Out-Null
Set-ProjectRegistryValue -Path $ap -Name "LetAppsAccessLocation" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $ap -Name "LetAppsGetDiagnosticInfo" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $ap -Name "LetAppsSyncWithDevices" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot
$ss = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"; New-Item -Path $ss -Force | Out-Null
Set-ProjectRegistryValue -Path $ss -Name "DisableSettingSync" -Value 2 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $ss -Name "DisableSettingSyncUserOverride" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; New-Item -Path $cdm -Force | Out-Null
Set-ProjectRegistryValue -Path $cdm -Name "RotatingLockScreenEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $cdm -Name "RotatingLockScreenOverlayEnabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; New-Item -Path $cc -Force | Out-Null
Set-ProjectRegistryValue -Path $cc -Name "DisableWindowsSpotlightFeatures" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot

Write-ProjectLog -Level INFO -Message "Showing file extensions/hidden files and disabling mouse acceleration"
Write-Host "[2/3] Showing file extensions/hidden files and disabling mouse acceleration..." -ForegroundColor Yellow
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; New-Item -Path $adv -Force | Out-Null
Set-ProjectRegistryValue -Path $adv -Name "HideFileExt" -Value 0 -ValueKind DWord -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $adv -Name "Hidden" -Value 1 -ValueKind DWord -Snapshot $registrySnapshot
$mp = "HKCU:\Control Panel\Mouse"
Set-ProjectRegistryValue -Path $mp -Name "MouseSpeed" -Value "0" -ValueKind String -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $mp -Name "MouseThreshold1" -Value "0" -ValueKind String -Snapshot $registrySnapshot
Set-ProjectRegistryValue -Path $mp -Name "MouseThreshold2" -Value "0" -ValueKind String -Snapshot $registrySnapshot
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class MouseHelper { [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d); }'
[MouseHelper]::SystemParametersInfo(0x0004, 0, @(0, 0, 0), 3) | Out-Null

Write-ProjectLog -Level INFO -Message "Cleaning temp files, Windows Update caches, and WinSxS"
Write-Host "[3/3] Cleaning temp files, Windows Update caches, and WinSxS..." -ForegroundColor Yellow
Get-ChildItem -Path "$env:TEMP" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "$env:SystemRoot\Temp" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$serviceNames = @("wuauserv", "bits", "dosvc")
$serviceWasRunning = @{}
foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        $serviceWasRunning[$name] = ($svc.Status -eq "Running")
        if ($svc.Status -eq "Running") { Stop-Service -Name $name -Force -ErrorAction Stop }
    }
}
try {
    foreach ($cachePath in @("$env:SystemRoot\SoftwareDistribution\Download", "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization")) {
        if (Test-Path -LiteralPath $cachePath) {
            Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} finally {
    Restore-ProjectServiceStates -WasRunning $serviceWasRunning -ServiceNames $serviceNames
}
Invoke-ProjectNativeCommand -FilePath "Dism.exe" -ArgumentList @("/Online", "/Cleanup-Image", "/StartComponentCleanup") -ContinueOnError | Out-Null
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Final tweaks applied and disk space cleaned. ===" -ForegroundColor Green