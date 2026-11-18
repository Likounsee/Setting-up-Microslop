#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
Write-Host "=== Installing Lightweight Microsoft 365 (Word, Excel, PowerPoint Only) ===" -ForegroundColor Cyan

$workDir = "$env:TEMP\ODT-Light"
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
Set-Location -Path $workDir

Write-Host "[1/3] Downloading Office Deployment Tool (ODT)..." -ForegroundColor Yellow
$odtExe = Join-Path $workDir "odt.exe"
Invoke-WebRequest -Uri "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe" -OutFile $odtExe -UseBasicParsing
Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$workDir`"" -Wait

Write-Host "[2/3] Generating minimal XML configuration (FR base + EN/DE proofing)..." -ForegroundColor Yellow
$xmlConfig = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="fr-fr" />
      <Language ID="en-us" Type="Proofing" />
      <Language ID="de-de" Type="Proofing" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Bing" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Teams" />
    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@
$xmlPath = Join-Path $workDir "config.xml"
[System.IO.File]::WriteAllText($xmlPath, $xmlConfig, [System.Text.UTF8Encoding]::new($false))

Write-Host "[3/3] Running Office setup..." -ForegroundColor Yellow
$proc = Start-Process -FilePath (Join-Path $workDir "setup.exe") -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
Set-Location -Path $env:TEMP
Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`n=== Done! Lightweight Office 365 setup finished (Exit code $($proc.ExitCode)). ===" -ForegroundColor Green