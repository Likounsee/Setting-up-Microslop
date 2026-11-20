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
Write-Host "=== Removing Microsoft Edge (Keeping WebView2 Runtime) ===" -ForegroundColor Cyan

Write-ProjectLog -Level INFO -Message "Stopping Edge processes"
Write-Host "[1/4] Stopping Edge processes..." -ForegroundColor Yellow
@("msedge", "msedgewebview2", "MicrosoftEdgeUpdate") | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

Write-ProjectLog -Level INFO -Message "Uninstalling Microsoft Edge browser"
Write-Host "[2/4] Uninstalling Microsoft Edge browser..." -ForegroundColor Yellow
@("${env:ProgramFiles(x86)}\Microsoft\Edge\Application", "$env:ProgramFiles\Microsoft\Edge\Application") | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem -Path $_ -Directory | ForEach-Object {
            $setupExe = Join-Path $_.FullName "Installer\setup.exe"
            if (Test-Path $setupExe) { Start-Process -FilePath $setupExe -ArgumentList "--uninstall --system-level --verbose-logging --force-uninstall" -Wait }
        }
    }
}
Get-AppxPackage -AllUsers -Name "*MicrosoftEdge*" | Where-Object { $_.NonRemovable -eq $false -and $_.InstallLocation -notlike "*\SystemApps\*" } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*MicrosoftEdge*" -and $_.DisplayName -notlike "*DevTools*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null

Write-ProjectLog -Level INFO -Message "Blocking Edge reinstallation via Windows Update"
Write-Host "[3/4] Blocking Edge reinstallation via Windows Update..." -ForegroundColor Yellow
$edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
New-Item -Path $edgePolicy -Force | Out-Null
Set-ItemProperty -Path $edgePolicy -Name "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -Type DWord
Set-ItemProperty -Path $edgePolicy -Name "Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -Type DWord
Set-ItemProperty -Path $edgePolicy -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord

Write-ProjectLog -Level INFO -Message "Verifying WebView2 Runtime & enabling updates"
Write-Host "[4/4] Verifying WebView2 Runtime & enabling updates..." -ForegroundColor Yellow
Set-ItemProperty -Path $edgePolicy -Name "Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -Value 1 -Type DWord
Set-ItemProperty -Path $edgePolicy -Name "Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -Value 1 -Type DWord
if (-not (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}")) {
    winget install --id Microsoft.EdgeWebView2Runtime --silent --accept-package-agreements --accept-source-agreements
}
Complete-ProjectLogging -Message "Script reached its completion message."
Write-Host "`n=== Done! Edge removed and blocked, WebView2 preserved. ===" -ForegroundColor Green