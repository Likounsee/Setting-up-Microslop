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
$ErrorActionPreference = "Stop"
Write-Host "=== Installing Lightweight Microsoft 365 (Word, Excel, PowerPoint Only) ===" -ForegroundColor Cyan

do {
    $langChoice = (Read-Host "Choose Office language: [FR] French or [EN] English").Trim().ToUpper()
} while ($langChoice -notin @("FR", "EN"))

if ($langChoice -eq "FR") {
    $langId    = "fr-fr"
    $langLabel = "French (fr-fr)"
} else {
    $langId    = "en-us"
    $langLabel = "English (en-us)"
}

Write-Host "Selected language: $langLabel" -ForegroundColor Green

$workDir = Join-Path $env:TEMP ("ODT-Light-" + (Get-Date -Format "yyyyMMddHHmmss"))
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
Set-Location -Path $workDir

Write-ProjectLog -Level INFO -Message "Resolving latest Office Deployment Tool download URL"
Write-Host "[1/3] Downloading Office Deployment Tool (ODT)..." -ForegroundColor Yellow

$odtUrl = $null
try {
    $detailsPage = Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/download/details.aspx?id=49117" -UseBasicParsing -TimeoutSec 20
    $match = [regex]::Match($detailsPage.Content, 'https://download\.microsoft\.com/download/[^"''\s]+/officedeploymenttool_[^"''\s]+\.exe')
    if ($match.Success) {
        $odtUrl = $match.Value
    }
} catch {
    Write-ProjectLog -Level WARNING -Message ("Dynamic ODT URL lookup failed, falling back to known URL: " + $_.Exception.Message)
}

if ([string]::IsNullOrWhiteSpace($odtUrl)) {
    $odtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_18129-20030.exe"
}

Write-ProjectLog -Level INFO -Message "Downloading ODT from: $odtUrl"
$odtExe = Join-Path $workDir "odt.exe"
Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe -UseBasicParsing

if (-not (Test-Path -LiteralPath $odtExe) -or (Get-Item -LiteralPath $odtExe).Length -lt 500KB) {
    throw "Downloaded ODT executable is missing or invalid (file size too small)."
}

Write-ProjectLog -Level INFO -Message "Extracting Office Deployment Tool"
$extractProc = Start-Process -FilePath $odtExe -ArgumentList @("/quiet", "/extract:`"$workDir`"") -Wait -PassThru -ErrorAction Stop
if ($extractProc.ExitCode -ne 0) {
    throw "ODT extraction failed with exit code $($extractProc.ExitCode)."
}

$setupExe = Join-Path $workDir "setup.exe"
if (-not (Test-Path -LiteralPath $setupExe)) {
    throw "ODT extracted successfully but setup.exe was not found in $workDir."
}

Write-ProjectLog -Level INFO -Message "Generating minimal XML configuration"
Write-Host "[2/3] Generating minimal XML configuration ($langLabel only)..." -ForegroundColor Yellow
$xmlConfig = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="$langId" />
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

Write-ProjectLog -Level INFO -Message "Running Office setup"
Write-Host "[3/3] Running Office setup..." -ForegroundColor Yellow
$setupProc = Start-Process -FilePath $setupExe -ArgumentList @("/configure", "`"$xmlPath`"") -Wait -PassThru -ErrorAction Stop
$officeExitCode = $setupProc.ExitCode

Set-Location -Path $env:TEMP
Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

if ($officeExitCode -notin @(0, 3010)) {
    throw "Office setup failed with exit code $officeExitCode."
}

Complete-ProjectLogging -Message "Office setup process returned exit code $officeExitCode."
Write-Host "`n=== Done! Lightweight Office 365 ($langLabel) finished (Exit code $officeExitCode). ===" -ForegroundColor Green