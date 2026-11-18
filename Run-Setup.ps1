#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# Ensure the current working directory is the script's directory (repo root)
Set-Location -Path $PSScriptRoot

# Define modules in the recommended execution order
$modules = @(
    @{
        File        = "Remove-EdgeKeepWebView.ps1"
        Title       = "Remove Microsoft Edge"
        Description = "Uninstalls Edge and blocks reinstallation while keeping WebView2 Runtime updated."
    },
    @{
        File        = "Remove-OneDriveComplete.ps1"
        Title       = "Complete OneDrive Removal"
        Description = "Uninstalls OneDrive, cleans up leftovers, and restores Desktop/Documents/Pictures to local paths."
    },
    @{
        File        = "Remove-XboxComplete.ps1"
        Title       = "Remove Xbox & Game Bar"
        Description = "Removes Xbox apps and Game Bar pop-ups while keeping Minecraft authentication working."
    },
    @{
        File        = "Remove-WindowsBloatware.ps1"
        Title       = "Remove Copilot, Recall & Bloatware"
        Description = "Kills and deletes Copilot, Recall, Widgets, sponsored shortcuts, and preinstalled apps."
    },
    @{
        File        = "Install-OfficeLight.ps1"
        Title       = "Install Lightweight Office 365"
        Description = "Installs only Word, Excel, and PowerPoint in French (with English and German proofing tools)."
    },
    @{
        File        = "Optimize-WindowsSystem.ps1"
        Title       = "System & Power Optimization"
        Description = "Disables telemetry, P2P updates, SysMain, hibernation, and adapts power plan (Desktop vs Laptop)."
    },
    @{
        File        = "Finalize-WindowsClean.ps1"
        Title       = "Final Tweaks & Disk Cleanup"
        Description = "Locks down sensors/Spotlight, shows file extensions, disables mouse acceleration, and cleans WinSxS."
    }
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
        Write-Host "[MISSING] $($mod.File) not found in repository root - skipped." -ForegroundColor DarkGray
        continue
    }

    Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Module  : $($mod.Title) ($($mod.File))" -ForegroundColor White
    Write-Host "Action  : $($mod.Description)" -ForegroundColor Gray

    do {
        $choice = (Read-Host "Run this script? [Y/N]").Trim().ToUpper()
    } while ($choice -notin @("Y", "N"))

    if ($choice -eq "Y") {
        $selectedModules += $mod
        Write-Host "-> Selected" -ForegroundColor Green
    } else {
        Write-Host "-> Skipped" -ForegroundColor DarkYellow
    }
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
if ($selectedModules.Count -eq 0) {
    Write-Host "No scripts selected. Operation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host "Selected scripts queued for execution ($($selectedModules.Count)):" -ForegroundColor Cyan
foreach ($sel in $selectedModules) {
    Write-Host "  • $($sel.Title) ($($sel.File))" -ForegroundColor White
}

Write-Host ""
$confirm = (Read-Host "Start execution now? [Y/N]").Trim().ToUpper()
if ($confirm -ne "Y") {
    Write-Host "Execution cancelled by user." -ForegroundColor Yellow
    exit 0
}

# Run selected scripts sequentially
$step = 1
foreach ($sel in $selectedModules) {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $sel.File
    Write-Host "`n>>> [$step/$($selectedModules.Count)] Running $($sel.File)..." -ForegroundColor Cyan

    try {
        & $scriptPath
    } catch {
        Write-Host "[ERROR] Failed while running $($sel.File): $_" -ForegroundColor Red
    }

    $step++
}

Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host " All selected scripts have finished executing!" -ForegroundColor Green
Write-Host " A system reboot is recommended to finalize all changes." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
