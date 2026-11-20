# Reversible backup helpers for approved AppData package directories.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Get-ProjectCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-ProjectTreeFileManifest {
    param([Parameter(Mandatory = $true)][string]$Root)
    $files = @()
    $allItems = @(Get-Item -LiteralPath $Root -Force -ErrorAction Stop) + @(Get-ChildItem -LiteralPath $Root -Force -Recurse -ErrorAction Stop)
    foreach ($item in $allItems) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not supported in filesystem backups: $($item.FullName)"
        }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring($Root.Length).TrimStart([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $files += [ordered]@{ RelativePath = $relative; Length = [long]$item.Length; SHA256 = $hash }
        }
    }
    return ,$files
}

function Save-ProjectFileSystemManifest {
    param([Parameter(Mandatory = $true)][string]$BackupRoot, [Parameter(Mandatory = $true)]$Manifest)
    $path = Join-Path $BackupRoot "manifest.json"
    $temporary = $path + ".tmp"
    [System.IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Manifest -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force -ErrorAction Stop
    return $path
}

function Backup-ProjectPackageDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$PackagesRoot,
        [Parameter(Mandatory = $true)][string]$BackupDirectory
    )

    $root = Get-ProjectCanonicalPath -Path $PackagesRoot
    $target = Get-ProjectCanonicalPath -Path $TargetPath
    if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($target), $root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Only direct children of the approved Packages root can be backed up."
    }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { return $null }

    $files = Get-ProjectTreeFileManifest -Root $target
    $backupRoot = Join-Path (Get-ProjectCanonicalPath -Path $BackupDirectory) ([guid]::NewGuid().ToString("N"))
    $itemsRoot = Join-Path $backupRoot "items"
    New-Item -ItemType Directory -Path $itemsRoot -Force -ErrorAction Stop | Out-Null
    $storedPath = Join-Path $itemsRoot "package"
    try {
        Copy-Item -LiteralPath $target -Destination $storedPath -Recurse -Force -ErrorAction Stop
        $copiedFiles = Get-ProjectTreeFileManifest -Root $storedPath
        if ($copiedFiles.Count -ne $files.Count) { throw "Backup verification failed: file count differs." }
        foreach ($entry in $files) {
            $copy = $copiedFiles | Where-Object { [string]::Equals($_.RelativePath, $entry.RelativePath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            if ($null -eq $copy -or $copy.Length -ne $entry.Length -or $copy.SHA256 -ne $entry.SHA256) {
                throw "Backup verification failed for file: $($entry.RelativePath)"
            }
        }
        $manifest = [ordered]@{
            Format = "Microslop.FileSystemBackup"
            Version = 1
            CreatedUtc = [DateTime]::UtcNow.ToString("o")
            PackagesRoot = $root
            Entries = @([ordered]@{
                OriginalPath = $target
                StoredPath = "items/package"
                State = "BackedUp"
                Files = $files
            })
        }
        Save-ProjectFileSystemManifest -BackupRoot $backupRoot -Manifest $manifest | Out-Null
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        $manifest.Entries[0].State = "Removed"
        Save-ProjectFileSystemManifest -BackupRoot $backupRoot -Manifest $manifest | Out-Null
        if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
            Write-ProjectLog -Level INFO -Message "Package directory backed up and removed; verified file count $($files.Count): $target"
        }
        return $backupRoot
    } catch {
        # Never discard the verified copy on failure: Remove-Item may have partially
        # deleted the source before reporting an error.
        throw
    }
}

function Restore-ProjectFileSystemBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupRoot,
        [Parameter(Mandatory = $true)][string]$PackagesRoot
    )
    $backup = Get-ProjectCanonicalPath -Path $BackupRoot
    $root = Get-ProjectCanonicalPath -Path $PackagesRoot
    $manifestPath = Join-Path $backup "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Filesystem backup manifest not found." }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.Format -ne "Microslop.FileSystemBackup" -or $manifest.Version -ne 1 -or $null -eq $manifest.Entries) {
        throw "Unsupported or invalid filesystem backup manifest."
    }
    if (-not [string]::Equals([string]$manifest.PackagesRoot, $root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup Packages root does not match the requested restore root."
    }
    $restored = 0
    foreach ($entry in @($manifest.Entries)) {
        $destination = Get-ProjectCanonicalPath -Path ([string]$entry.OriginalPath)
        if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($destination), $root, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest contains a destination outside the approved Packages root."
        }
        if (Test-Path -LiteralPath $destination) {
            Write-Warning "Restore skipped because destination already exists: $destination"
            continue
        }
        $relativeStored = [string]$entry.StoredPath
        if ([System.IO.Path]::IsPathRooted($relativeStored) -or $relativeStored -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Manifest contains an unsafe backup-relative path."
        }
        $source = Get-ProjectCanonicalPath -Path (Join-Path $backup $relativeStored)
        if (-not $source.StartsWith($backup + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Manifest backup data path is invalid or missing."
        }
        $actual = Get-ProjectTreeFileManifest -Root $source
        $expected = @($entry.Files)
        if ($actual.Count -ne $expected.Count) { throw "Backup integrity check failed: file count differs." }
        foreach ($file in $expected) {
            $match = $actual | Where-Object { [string]::Equals($_.RelativePath, [string]$file.RelativePath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            if ($null -eq $match -or $match.Length -ne [long]$file.Length -or $match.SHA256 -ne [string]$file.SHA256) {
                throw "Backup integrity check failed for: $($file.RelativePath)"
            }
        }
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop
        $restoredFiles = Get-ProjectTreeFileManifest -Root $destination
        if ($restoredFiles.Count -ne $expected.Count) {
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
            throw "Restore verification failed: file count differs."
        }
        foreach ($file in $expected) {
            $restoredFile = $restoredFiles | Where-Object { [string]::Equals($_.RelativePath, [string]$file.RelativePath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            if ($null -eq $restoredFile -or $restoredFile.Length -ne [long]$file.Length -or $restoredFile.SHA256 -ne [string]$file.SHA256) {
                Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
                throw "Restore verification failed for: $($file.RelativePath)"
            }
        }
        $restored++
        if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
            Write-ProjectLog -Level INFO -Message "Restored package directory from verified backup: $destination"
        }
    }
    return $restored
}
