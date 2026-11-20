# Keep diagnostics visible even when an unexpected terminating error occurs before the summary.
trap {
    $fatalError = $_
    Write-Host "`n[FATAL SETUP ERROR]" -ForegroundColor Red
    Write-Host ($fatalError | Out-String) -ForegroundColor Red
    if ($fatalError.InvocationInfo -and $fatalError.InvocationInfo.PositionMessage) {
        Write-Host $fatalError.InvocationInfo.PositionMessage -ForegroundColor Yellow
    }
    if ($fatalError.ScriptStackTrace) {
        Write-Host "Stack trace:" -ForegroundColor Yellow
        Write-Host $fatalError.ScriptStackTrace -ForegroundColor Yellow
    }
    try { Read-Host "`nAn unexpected error occurred. Press Enter to close" | Out-Null } catch {}
    exit 1
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
Set-Location -Path $PSScriptRoot

$sharedLogger = Join-Path $PSScriptRoot "Common\Logging.ps1"
if (Test-Path -LiteralPath $sharedLogger) {
    . $sharedLogger
    Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name -LogDirectory (Join-Path $PSScriptRoot "Logs") | Out-Null
    Write-ProjectLog -Level INFO -Message "Orchestrator initialized; detailed transcript is also enabled."
} else {
    Write-Warning "Shared logger not found at $sharedLogger"
}


$modules = @(
    @{ File = "Remove-EdgeKeepWebView.ps1"; Title = "Remove Microsoft Edge"; Description = "Uninstalls Edge and blocks reinstallation while keeping WebView2 Runtime updated." },
    @{ File = "Remove-OneDriveComplete.ps1"; Title = "Complete OneDrive Removal"; Description = "Uninstalls OneDrive, cleans leftovers, and restores Desktop/Documents/Pictures locally." },
    @{ File = "Remove-XboxComplete.ps1"; Title = "Remove Xbox & Game Bar"; Description = "Removes Xbox apps and Game Bar pop-ups while keeping Minecraft authentication working." },
    @{ File = "Remove-WindowsBloatware.ps1"; Title = "Remove Copilot, Recall & Bloatware"; Description = "Kills and deletes Copilot, Recall, Widgets, sponsored shortcuts, and preinstalled apps." },
    @{ File = "Install-OfficeLight.ps1"; Title = "Install Lightweight Office 365"; Description = "Installs only Word, Excel, and PowerPoint (prompts for French or English)." },
    @{ File = "Optimize-WindowsSystem.ps1"; Title = "System & Power Optimization"; Description = "Disables telemetry, P2P updates, SysMain, hibernation, and adapts power plan." },
    @{ File = "Finalize-WindowsClean.ps1"; Title = "Final Tweaks & Disk Cleanup"; Description = "Locks down sensors/Spotlight, shows extensions, disables mouse acceleration, cleans WinSxS." }
)

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "              WINDOWS SETUP & DEBLOAT ORCHESTRATOR" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Answer with [Y] (Yes) or [N] (No) for each module.`n" -ForegroundColor Gray

$selectedModules = @()
foreach ($mod in $modules) {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $mod.File
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[MISSING] $($mod.File) not found - skipped." -ForegroundColor DarkGray
        continue
    }
    Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Module  : $($mod.Title) ($($mod.File))" -ForegroundColor White
    Write-Host "Action  : $($mod.Description)" -ForegroundColor Gray
    do { $choice = (Read-Host "Run this script? [Y/N]").Trim().ToUpper() } while ($choice -notin @("Y", "N"))
    if ($choice -eq "Y") { $selectedModules += $mod; Write-Host "-> Selected" -ForegroundColor Green }
    else { Write-Host "-> Skipped" -ForegroundColor DarkYellow }
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
if ($selectedModules.Count -eq 0) { Write-Host "No scripts selected. Cancelled." -ForegroundColor Yellow; exit 0 }

Write-Host "Selected scripts ($($selectedModules.Count)):" -ForegroundColor Cyan
foreach ($sel in $selectedModules) { Write-Host "  - $($sel.Title) ($($sel.File))" -ForegroundColor White }

Write-Host ""
if ((Read-Host "Start execution now? [Y/N]").Trim().ToUpper() -ne "Y") { exit 0 }

# Keep a durable record of the orchestrator and every module's visible output.
$logRoot = Join-Path $PSScriptRoot "Logs"
if (-not (Test-Path -LiteralPath $logRoot)) {
    New-Item -Path $logRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$runLog = Join-Path $logRoot "Setup-$runId.log"
$transcriptStarted = $false
try {
    Start-Transcript -Path $runLog -Append -ErrorAction Stop | Out-Null
    $transcriptStarted = $true
} catch {
    Write-Warning "Could not start transcript logging: $($_.Exception.Message)"
}
Write-Host "Log file: $runLog" -ForegroundColor Gray

$results = @()
$step = 1
try {
    foreach ($sel in $selectedModules) {
        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $sel.File
        $moduleLog = Join-Path $logRoot ("{0}-{1}.log" -f $runId, [System.IO.Path]::GetFileNameWithoutExtension($sel.File))
        Write-Host "`n>>> [$step/$($selectedModules.Count)] Running $($sel.File)..." -ForegroundColor Cyan
        if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level INFO -Message ("Starting module: " + $sel.File) }
        Write-Host "Module log: $moduleLog" -ForegroundColor Gray
        try {
            # Capture all output streams that the module actually emits.
            & $scriptPath *>&1 | Tee-Object -FilePath $moduleLog -Append
            $results += [pscustomobject]@{ Module = $sel.File; Status = "Returned"; Log = $moduleLog; Error = "" }
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level INFO -Message ("Module returned: " + $sel.File) }
        } catch {
            $errorRecord = $_
            $errorText = $errorRecord | Out-String
            $diagnostic = @(
                "Module: $($sel.File)",
                "Exception type: $($errorRecord.Exception.GetType().FullName)",
                "Message: $($errorRecord.Exception.Message)"
            )
            if ($errorRecord.FullyQualifiedErrorId) { $diagnostic += "FullyQualifiedErrorId: $($errorRecord.FullyQualifiedErrorId)" }
            if ($errorRecord.InvocationInfo -and $errorRecord.InvocationInfo.PositionMessage) { $diagnostic += $errorRecord.InvocationInfo.PositionMessage }
            if ($errorRecord.ScriptStackTrace) { $diagnostic += "Stack trace:`n$($errorRecord.ScriptStackTrace)" }
            $diagnosticText = $diagnostic -join [Environment]::NewLine
            Write-Host "[ERROR] $diagnosticText" -ForegroundColor Red
            Add-Content -LiteralPath $moduleLog -Value ("`n[ORCHESTRATOR ERROR]`n" + $diagnosticText + "`nOriginal error record:`n" + $errorText) -ErrorAction SilentlyContinue
            $results += [pscustomobject]@{ Module = $sel.File; Status = "Failed"; Log = $moduleLog; Error = $diagnosticText }
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level ERROR -Message ("Module failed: " + $diagnosticText) }
        }
        $step++
    }

    Write-Host "`n==================== EXECUTION SUMMARY ====================" -ForegroundColor Cyan
    $results | Format-Table Module, Status, Log -AutoSize
    $failed = @($results | Where-Object Status -eq "Failed").Count
    if ($failed -gt 0) {
        Write-Host "$failed module(s) failed with a terminating PowerShell error. Review their logs." -ForegroundColor Red
    } else {
        Write-Host "Modules returned without a terminating PowerShell error. This does not prove every operation succeeded." -ForegroundColor Yellow
    }
    Write-Host "Run log: $runLog" -ForegroundColor Gray
    Write-Host "A reboot may be required." -ForegroundColor Yellow
    Read-Host "`nPress Enter to close"
    if ($failed -gt 0) { exit 1 }
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Could not close transcript cleanly: $($_.Exception.Message)" }
    }
}