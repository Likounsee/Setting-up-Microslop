#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InventoryPath,
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"
$helper = Join-Path $PSScriptRoot "Common\AppxRecovery.ps1"
$logger = Join-Path $PSScriptRoot "Common\Logging.ps1"
$journalHelper = Join-Path $PSScriptRoot "Common\OperationJournal.ps1"
if (-not (Test-Path -LiteralPath $helper)) { throw "Appx recovery helpers not found: $helper" }
if (-not (Test-Path -LiteralPath $journalHelper)) { throw "Operation journal helpers not found: $journalHelper" }
. $helper
. $journalHelper
if (Test-Path -LiteralPath $logger) {
    . $logger
    Initialize-ProjectLogging -ScriptName $MyInvocation.MyCommand.Name -LogDirectory (Join-Path $PSScriptRoot "Logs") | Out-Null
}

$inventory = Import-ProjectAppxInventory -Path $InventoryPath
$currentInstalled = @(Get-AppxPackage -AllUsers)
$currentProvisioned = @(Get-AppxProvisionedPackage -Online)
$plan = @(Get-ProjectAppxRecoveryPlan -Inventory $inventory -CurrentInstalledPackages $currentInstalled -CurrentProvisionedPackages $currentProvisioned)
$missing = @($plan | Where-Object { -not $_.PresentNow })

Write-Host ("Inventory created: {0}" -f $inventory.CreatedUtc) -ForegroundColor Cyan
Write-Host ("Packages inventoried: {0} installed, {1} provisioned" -f @($inventory.InstalledPackages).Count, @($inventory.ProvisionedPackages).Count)
Write-Host ("Missing compared with inventory: {0}" -f $missing.Count) -ForegroundColor Yellow
$plan | Format-Table PackageType, Name, PresentNow, OriginalInstallLocationExists, RecoveryHint -Wrap

if (-not [string]::IsNullOrWhiteSpace($CsvPath)) {
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($CsvPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $plan | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Recovery plan exported: $CsvPath" -ForegroundColor Green
}

Write-Warning "This is a recovery assessment only. It does not install packages or download binaries."
