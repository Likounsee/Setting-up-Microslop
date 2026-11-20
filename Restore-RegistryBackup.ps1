#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath,
    [switch]$Force
)

$registryScript = Join-Path $PSScriptRoot "Common\Registry.ps1"
if (-not (Test-Path -LiteralPath $registryScript)) {
    throw "Registry helpers not found: $registryScript"
}
. $registryScript

$resolvedBackupPath = (Resolve-Path -LiteralPath $BackupPath -ErrorAction Stop).Path
$snapshot = Import-ProjectRegistrySnapshot -Path $resolvedBackupPath
Write-Host "Backup: $resolvedBackupPath" -ForegroundColor Cyan
Write-Host "Registry values to restore: $($snapshot.Count)" -ForegroundColor Yellow
Write-Warning "This operation changes the Windows registry. Current values will be overwritten."
$confirmation = Read-Host 'Type RESTORE to continue'
if ($confirmation -cne "RESTORE") {
    Write-Host "Restoration cancelled. No registry values were changed." -ForegroundColor Gray
    exit 0
}

$restored = Restore-ProjectRegistrySnapshot -Snapshot $snapshot -Force:$Force
if ($restored) {
    Write-Host "Registry restoration completed." -ForegroundColor Green
    exit 0
}
Write-Warning "Restoration finished with one or more errors. Review the messages above."
exit 1
