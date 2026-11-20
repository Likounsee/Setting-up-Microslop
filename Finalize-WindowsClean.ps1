#Requires -RunAsAdministrator
$loggingScript = Join-Path $PSScriptRoot "Common\Logging.ps1"
if (Test-Path -LiteralPath $loggingScript) {
    . $loggingScript
    Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name | Out-Null
} else {
    Write-Warning "Shared logger not found at $loggingScript"
}
trap {
    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level ERROR -Message ("Unhandled terminating error: " + ($_ | Out-String).Trim())
    }
    throw
}
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== Final Tweaks (Privacy, File Extensions, 1:1 Mouse & Disk Cleanup) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Locking down sensor permissions, diagnostics, and lock screen Spotlight"
Write-Host "[1/3] Locking down sensor permissions, diagnostics, and lock screen Spotlight..." -ForegroundColor Yellow
$ap = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; New-Item -Path $ap -Force | Out-Null
Set-ItemProperty -Path $ap -Name "LetAppsAccessLocation" -Value 2 -Type DWord
Set-ItemProperty -Path $ap -Name "LetAppsGetDiagnosticInfo" -Value 2 -Type DWord
Set-ItemProperty -Path $ap -Name "LetAppsSyncWithDevices" -Value 2 -Type DWord
$ss = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"; New-Item -Path $ss -Force | Out-Null
Set-ItemProperty -Path $ss -Name "DisableSettingSync" -Value 2 -Type DWord
Set-ItemProperty -Path $ss -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; New-Item -Path $cdm -Force | Out-Null
Set-ItemProperty -Path $cdm -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $cdm -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord
$cc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; New-Item -Path $cc -Force | Out-Null
Set-ItemProperty -Path $cc -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord

Write-ProjectLog -Level INFO -Message "Showing file extensions/hidden files and disabling mouse acceleration"
Write-Host "[2/3] Showing file extensions/hidden files and disabling mouse acceleration..." -ForegroundColor Yellow
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; New-Item -Path $adv -Force | Out-Null
Set-ItemProperty -Path $adv -Name "HideFileExt" -Value 0 -Type DWord
Set-ItemProperty -Path $adv -Name "Hidden" -Value 1 -Type DWord
$mp = "HKCU:\Control Panel\Mouse"
Set-ItemProperty -Path $mp -Name "MouseSpeed" -Value "0" -Type String
Set-ItemProperty -Path $mp -Name "MouseThreshold1" -Value "0" -Type String
Set-ItemProperty -Path $mp -Name "MouseThreshold2" -Value "0" -Type String
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
    foreach ($name in $serviceNames) {
        if ($serviceWasRunning[$name]) { Start-Service -Name $name -ErrorAction SilentlyContinue }
    }
}
$cleanup = Start-Process -FilePath "Dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -Wait -PassThru -NoNewWindow
if ($cleanup.ExitCode -ne 0) { Write-Warning "DISM component cleanup returned exit code $($cleanup.ExitCode)." }
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Final tweaks applied and disk space cleaned. ===" -ForegroundColor Green