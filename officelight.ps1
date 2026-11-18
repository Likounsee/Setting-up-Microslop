#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# --- Configuration ---
$WorkDir = "$env:TEMP\ODT_AutoInstall"
$OdtExe  = "$WorkDir\setup.exe"
$XmlPath = "$WorkDir\config.xml"
$OdtPage = "https://www.microsoft.com/en-us/download/details.aspx?id=49117"

Write-Host "=== Installation légère Microsoft 365 (Word, Excel, PowerPoint) ===" -ForegroundColor Cyan

try {
    # 1. Préparation du dossier temporaire propre
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null

    # 2. Récupération et extraction automatique de l'Office Deployment Tool (ODT)
    Write-Host "[1/4] Téléchargement de l'Office Deployment Tool..." -ForegroundColor Yellow
    $html = (Invoke-WebRequest -Uri $OdtPage -UseBasicParsing).Content
    if ($html -match 'https://download\.microsoft\.com/download/[^"]+officedeploymenttool[^"]+\.exe') {
        $odtUrl = $matches[0]
    } else {
        throw "Impossible de récupérer le lien de téléchargement de l'ODT."
    }

    $installerPath = "$WorkDir\odt_installer.exe"
    Invoke-WebRequest -Uri $odtUrl -OutFile $installerPath -UseBasicParsing
    Start-Process -FilePath $installerPath -ArgumentList "/quiet /extract:`"$WorkDir`"" -Wait

    # 3. Génération du fichier de configuration XML (Word, Excel, PowerPoint + FR/EN/DE)
    Write-Host "[2/4] Génération de la configuration XML..." -ForegroundColor Yellow
    $xmlContent = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="fr-fr" />
      <Language ID="en-us" />
      <Language ID="de-de" />
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
  <Updates Enabled="TRUE" />
  <Display Level="Full" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1" />
  <Logging Level="Standard" Path="$WorkDir" />
</Configuration>
"@
    Set-Content -Path $XmlPath -Value $xmlContent -Encoding UTF8

    # 4. Lancement de l'installation et suivi de la progression
    Write-Host "[3/4] Installation en cours (Word, Excel, PowerPoint)..." -ForegroundColor Yellow
    $setupProc = Start-Process -FilePath $OdtExe -ArgumentList "/configure `"$XmlPath`"" -PassThru

    $lastPercent = -1
    while (-not $setupProc.HasExited) {
        $logFile = Get-ChildItem "$WorkDir\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($logFile) {
            $lines = Get-Content $logFile.FullName -Tail 30 -ErrorAction SilentlyContinue
            $progressLine = $lines | Where-Object { $_ -match "total progress is now (\d+)" } | Select-Object -Last 1
            if ($progressLine -and $matches[1] -ne $lastPercent) {
                $lastPercent = $matches[1]
                Write-Host "      Progression globale : $lastPercent %" -ForegroundColor Green
            }
        }
        Start-Sleep -Seconds 3
    }

    if ($setupProc.ExitCode -ne 0) {
        throw "L'installation s'est terminée avec le code d'erreur : $($setupProc.ExitCode)"
    }

    Write-Host "      Installation terminée avec succès (100 %)." -ForegroundColor Green
}
finally {
    # 5. Nettoyage complet des fichiers temporaires et journaux ODT
    Write-Host "[4/4] Nettoyage des fichiers temporaires..." -ForegroundColor Yellow
    if (Test-Path $WorkDir) {
        Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem "$env:TEMP\PC-*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Vérification finale des exécutables installés
Write-Host "`n=== Vérification des applications installées ===" -ForegroundColor Cyan
Get-ChildItem "C:\Program Files\Microsoft Office\root\Office16\*.exe" -ErrorAction SilentlyContinue |
    Where-Object Name -match "^(WINWORD|EXCEL|POWERPNT|OUTLOOK|ONENOTE|MSPUB|MSACCESS|LYNC)\.EXE$" |
    ForEach-Object { Write-Host " - $($_.Name)" -ForegroundColor White }
