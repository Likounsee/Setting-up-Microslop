# Safety entry point for AppData package-directory cleanup.
# Actual deletion is performed only after a verified, persistent backup exists.
$backupScript = Join-Path $PSScriptRoot "FileSystemBackup.ps1"
if (-not (Test-Path -LiteralPath $backupScript)) { throw "Filesystem backup helpers not found: $backupScript" }
. $backupScript

function Remove-ProjectPackageDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$PackagesRoot,
        [Parameter(Mandatory = $true)][string]$BackupDirectory
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        Write-Warning "Skipped package cleanup: empty target path."
        return $false
    }
    try {
        $root = Get-ProjectCanonicalPath -Path $PackagesRoot
        $target = Get-ProjectCanonicalPath -Path $TargetPath
        if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($target), $root, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Skipped cleanup outside the Packages root: $TargetPath"
            return $false
        }
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { return $true }
        Backup-ProjectPackageDirectory -TargetPath $target -PackagesRoot $root -BackupDirectory $BackupDirectory | Out-Null
        return $true
    } catch {
        Write-Warning "Could not safely back up and remove package directory '$TargetPath': $($_.Exception.Message)"
        return $false
    }
}
