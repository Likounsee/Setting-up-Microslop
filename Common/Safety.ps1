# Safety helpers for filesystem operations.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Remove-ProjectPackageDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$PackagesRoot
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        Write-Warning "Skipped package cleanup: empty target path."
        return $false
    }

    try {
        $root = [System.IO.Path]::GetFullPath($PackagesRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $target = [System.IO.Path]::GetFullPath($TargetPath)
        $parent = [System.IO.Path]::GetDirectoryName($target)
        if (-not [string]::Equals($parent.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar), $root, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Skipped cleanup outside the Packages root: $TargetPath"
            return $false
        }

        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            return $true
        }

        $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Skipped reparse-point package directory: $target"
            return $false
        }

        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Could not remove package directory '$TargetPath': $($_.Exception.Message)"
        return $false
    }
}
