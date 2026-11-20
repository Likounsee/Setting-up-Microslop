#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupDirectory
)

$helper = Join-Path $PSScriptRoot "Common\FileSystemBackup.ps1"
if (-not (Test-Path -LiteralPath $helper)) { throw "Filesystem backup helpers not found: $helper" }
. $helper
$resolved = (Resolve-Path -LiteralPath $BackupDirectory -ErrorAction Stop).Path
$manifestPath = Join-Path $resolved "manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Backup manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
Write-Host "Filesystem backup: $resolved" -ForegroundColor Cyan
Write-Host "Package directories recorded: $(@($manifest.Entries).Count)" -ForegroundColor Yellow
Write-Warning "Restore only targets the original direct-child locations under the recorded Packages root. Existing destinations are skipped."
$confirmation = Read-Host 'Type RESTORE to continue'
if ($confirmation -cne "RESTORE") {
    Write-Host "Restoration cancelled. No files were changed." -ForegroundColor Gray
    exit 0
}
$count = Restore-ProjectFileSystemBackup -BackupRoot $resolved -PackagesRoot ([string]$manifest.PackagesRoot)
Write-Host "Restored package directories: $count" -ForegroundColor Green
