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
    try {
        $elevatedProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait -PassThru -ErrorAction Stop
        exit $elevatedProcess.ExitCode
    } catch {
        Write-Host "Could not start the elevated setup process: $($_.Exception.Message)" -ForegroundColor Red
        try { Read-Host "Press Enter to close" | Out-Null } catch {}
        exit 1
    }
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

$setupDiagnostics = Join-Path $PSScriptRoot "Common\SetupDiagnostics.ps1"
if (Test-Path -LiteralPath $setupDiagnostics) {
    . $setupDiagnostics
} else {
    throw "Required diagnostics helper not found: $setupDiagnostics"
}


$modules = @(
    @{ File = "Remove-EdgeKeepWebView.ps1"; Title = "Remove Microsoft Edge"; Description = "Uninstalls Edge and blocks reinstallation while keeping WebView2 Runtime updated." },
    @{ File = "Remove-OneDriveComplete.ps1"; Title = "Complete OneDrive Removal"; Description = "Uninstalls OneDrive, cleans leftovers, and restores Desktop/Documents/Pictures locally." },
    @{ File = "Remove-XboxComplete.ps1"; Title = "Remove Xbox & Game Bar"; Description = "Removes Xbox apps and Game Bar pop-ups while keeping Minecraft authentication working." },
    @{ File = "Remove-WindowsBloatware.ps1"; Title = "Remove Copilot, Recall & Bloatware"; Description = "Kills and deletes Copilot, Recall, Widgets, sponsored shortcuts, and preinstalled apps." },
    @{ File = "Install-OfficeLight.ps1"; Title = "Install Lightweight Office 365"; Description = "Installs only Word, Excel, and PowerPoint (prompts for French or English)." },
    @{ File = "Optimize-WindowsSystem.ps1"; Title = "System & Power Optimization"; Description = "Disables telemetry, P2P updates, SysMain, hibernation, and adapts power plan." },
    @{ File = "Set-AmdGpuStability.ps1"; Title = "AMD GPU Stability Tweaks"; Description = "Detects AMD GPUs and backs up/applies MPO, HAGS, and ULPS registry workarounds." },
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
            # Capture all streams while keeping module output visible in the console and log.
            $moduleOutput = New-Object 'System.Collections.Generic.List[object]'
            & $scriptPath *>&1 |
                ForEach-Object {
                    [void]$moduleOutput.Add($_)
                    $_
                } |
                Tee-Object -FilePath $moduleLog -Append

            # A script can return normally while still emitting non-terminating errors.
            $moduleErrors = @(Get-ProjectErrorRecords -Output $moduleOutput.ToArray())
            if ($moduleErrors.Count -gt 0) {
                $errorText = ($moduleErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                Write-Host "[WARN] $($sel.File) returned with $($moduleErrors.Count) PowerShell error record(s)." -ForegroundColor Yellow
                $results += [pscustomobject]@{ Module = $sel.File; Status = "CompletedWithErrors"; Log = $moduleLog; Error = $errorText }
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level WARNING -Message ("Module returned with error records: " + $sel.File + " :: " + $errorText) }
            } else {
                $results += [pscustomobject]@{ Module = $sel.File; Status = "Returned"; Log = $moduleLog; Error = "" }
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level INFO -Message ("Module returned: " + $sel.File) }
            }
        } catch {
            $errorRecord = $_
            $errorText = $errorRecord | Out-String
            $diagnosticText = Format-ProjectErrorRecord -ErrorRecord $errorRecord -ModuleName $sel.File
            Write-Host "[ERROR] $diagnosticText" -ForegroundColor Red
            Add-Content -LiteralPath $moduleLog -Value ("`n[ORCHESTRATOR ERROR]`n" + $diagnosticText + "`nOriginal error record:`n" + $errorText) -ErrorAction SilentlyContinue
            $results += [pscustomobject]@{ Module = $sel.File; Status = "Failed"; Log = $moduleLog; Error = $diagnosticText }
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) { Write-ProjectLog -Level ERROR -Message ("Module failed: " + $diagnosticText) }
        }
        $step++
    }

    Write-Host "`n==================== EXECUTION SUMMARY ====================" -ForegroundColor Cyan
    $results | Format-Table Module, Status, Log -AutoSize
    foreach ($problem in @($results | Where-Object { $_.Status -in @("Failed", "CompletedWithErrors") })) {
        $firstErrorLine = ($problem.Error -split "`r?`n" | Select-Object -First 1)
        if ($firstErrorLine) {
            Write-Host ("  {0}: {1}" -f $problem.Module, $firstErrorLine) -ForegroundColor Yellow
        }
    }
    $failed = @($results | Where-Object { $_.Status -in @("Failed", "CompletedWithErrors") }).Count
    if ($failed -gt 0) {
        Write-Host "$failed module(s) reported PowerShell errors or failed with a terminating error. Review their logs." -ForegroundColor Red
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