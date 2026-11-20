# Conservative cleanup for explicitly approved temporary directories.
# Only top-level entries older than the requested age are removed.
# Any entry containing a reparse point is skipped to avoid traversing links.

function Remove-ProjectStaleTemporaryItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedPaths,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [ValidateRange(1, 3650)][int]$MinimumAgeDays = 7
    )

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $allowed = $false
    foreach ($allowedPath in $AllowedPaths) {
        $candidate = [System.IO.Path]::GetFullPath($allowedPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ([string]::Equals($root, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) { throw "Temporary cleanup path is not explicitly allowlisted: $root" }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject]@{ Removed = 0; Skipped = 0; Failed = 0 }
    }

    $cutoff = (Get-Date).AddDays(-$MinimumAgeDays)
    $removed = 0
    $skipped = 0
    $failed = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
        try {
            $tree = @($item)
            if ($item.PSIsContainer) {
                $tree += @(Get-ChildItem -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop)
            }
            $hasReparsePoint = $false
            $latestWrite = $item.LastWriteTime
            foreach ($node in $tree) {
                if (($node.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $hasReparsePoint = $true
                    break
                }
                if ($node.LastWriteTime -gt $latestWrite) { $latestWrite = $node.LastWriteTime }
            }
            if ($hasReparsePoint -or $latestWrite -ge $cutoff) {
                $skipped++
                Write-ProjectOperationRecord -JournalPath $JournalPath -Operation "Temporary cleanup" -Category Regenerable -Status Skipped -Target $item.FullName -Details $(if ($hasReparsePoint) { "Contains a reparse point." } else { "Contains data newer than $MinimumAgeDays days." }) | Out-Null
                continue
            }

            Write-ProjectOperationRecord -JournalPath $JournalPath -Operation "Temporary cleanup" -Category Regenerable -Status Started -Target $item.FullName -Details "Older than $MinimumAgeDays days." | Out-Null
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $item.FullName) { throw "Entry still exists after removal." }
            Write-ProjectOperationRecord -JournalPath $JournalPath -Operation "Temporary cleanup" -Category Regenerable -Status Completed -Target $item.FullName -Details "Removed stale temporary entry." | Out-Null
            $removed++
        } catch {
            $failed++
            Write-ProjectOperationRecord -JournalPath $JournalPath -Operation "Temporary cleanup" -Category Regenerable -Status Failed -Target $item.FullName -Details $_.Exception.Message | Out-Null
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                Write-ProjectLog -Level WARNING -Message ("Temporary entry was not removed: {0} ({1})" -f $item.FullName, $_.Exception.Message)
            }
        }
    }
    return [pscustomobject]@{ Removed = $removed; Skipped = $skipped; Failed = $failed }
}
