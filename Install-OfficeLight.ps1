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

$workDir = "$env:TEMP\ODT-Light"
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
Set-Location -Path $workDir

Write-ProjectLog -Level INFO -Message "Downloading Office Deployment Tool"
Write-Host "[1/3] Downloading Office Deployment Tool (ODT)..." -ForegroundColor Yellow
$odtExe = Join-Path $workDir "odt.exe"
Invoke-WebRequest -Uri "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe" -OutFile $odtExe -UseBasicParsing
Invoke-ProjectNativeCommand -FilePath $odtExe -ArgumentList @("/quiet", "/extract:$workDir") | Out-Null

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
$officeExitCode = Invoke-ProjectNativeCommand -FilePath (Join-Path $workDir "setup.exe") -ArgumentList @("/configure", $xmlPath)
Set-Location -Path $env:TEMP
Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
Complete-ProjectLogging -Message "Office setup process returned exit code $officeExitCode."
Write-Host "`n=== Done! Lightweight Office 365 ($langLabel) finished (Exit code $officeExitCode). ===" -ForegroundColor Green