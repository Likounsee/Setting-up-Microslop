#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath
)

$serviceScript = Join-Path $PSScriptRoot "Common\ServiceState.ps1"
if (-not (Test-Path -LiteralPath $serviceScript)) {
    throw "Service-state helpers not found: $serviceScript"
}
. $serviceScript

$resolvedBackupPath = (Resolve-Path -LiteralPath $BackupPath -ErrorAction Stop).Path
$snapshot = Import-ProjectServiceSnapshot -Path $resolvedBackupPath
Write-Host "Backup: $resolvedBackupPath" -ForegroundColor Cyan
Write-Host "Services recorded: $($snapshot.Count)" -ForegroundColor Yellow
$toStart = @($snapshot.Keys | Where-Object { $snapshot[$_] })
Write-Host "Services that were running and will be started: $($toStart -join ', ')" -ForegroundColor Cyan
Write-Warning "This operation starts services that were running when the backup was created. It does not stop services."
$confirmation = Read-Host 'Type RESTORE to continue'
if ($confirmation -cne "RESTORE") {
    Write-Host "Restoration cancelled. No service states were changed." -ForegroundColor Gray
    exit 0
}

Restore-ProjectServiceSnapshot -Snapshot $snapshot
Write-Host "Service restoration requested. Check the service states above if any service failed to start." -ForegroundColor Green
