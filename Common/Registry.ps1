# Registry helpers with in-memory snapshots, persistent backups and read-back verification.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Get-ProjectRegistrySnapshotKey {
    param([string]$Path, [string]$Name)
    return ($Path.TrimEnd('\') + '|' + $Name)
}

function Set-ProjectRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value,
        [ValidateSet('DWord', 'String', 'ExpandString', 'QWord', 'MultiString', 'Binary')]
        [string]$ValueKind = 'DWord',
        [hashtable]$Snapshot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    $snapshotKey = Get-ProjectRegistrySnapshotKey -Path $Path -Name $Name
    if (($null -ne $Snapshot) -and -not $Snapshot.ContainsKey($snapshotKey)) {
        $exists = $false
        $oldValue = $null
        $oldKind = $null
        $providerPath = $Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
        $key = $null
        try {
            $key = Get-Item -LiteralPath $providerPath -ErrorAction Stop
            $exists = $key.GetValueNames() -contains $Name
            if ($exists) {
                $oldValue = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $oldKind = [string]$key.GetValueKind($Name)
            }
        } finally {
            if ($key -is [System.IDisposable]) { $key.Dispose() }
        }
        $Snapshot[$snapshotKey] = @{
            Path = $Path; Name = $Name; Exists = $exists
            Value = $oldValue; ValueKind = $oldKind
        }
    }

    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $ValueKind -Force -ErrorAction Stop | Out-Null
    $actual = Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
    if ($ValueKind -eq 'Binary' -or $ValueKind -eq 'MultiString') {
        $matches = [System.Linq.Enumerable]::SequenceEqual([object[]]$actual, [object[]]$Value)
    } else {
        $matches = ($actual -eq $Value)
    }
    if (-not $matches) { throw "Registry verification failed for '$Path\$Name'." }

    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level INFO -Message ("Registry value verified: {0}\{1} ({2})" -f $Path, $Name, $ValueKind)
    }
    return $true
}

function ConvertTo-ProjectRegistryBackupEntry {
    param([Parameter(Mandatory = $true)][hashtable]$Entry)

    $serializedValue = $Entry.Value
    if ($Entry.Exists -and $Entry.ValueKind -eq 'Binary') {
        $serializedValue = [Convert]::ToBase64String([byte[]]$Entry.Value)
    } elseif ($Entry.Exists -and $Entry.ValueKind -eq 'MultiString') {
        $serializedValue = @($Entry.Value)
    }
    return [ordered]@{
        Path = [string]$Entry.Path
        Name = [string]$Entry.Name
        Exists = [bool]$Entry.Exists
        ValueKind = $Entry.ValueKind
        Value = $serializedValue
    }
}

function Save-ProjectRegistrySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { throw "Backup path must include a directory." }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    }

    $entries = @()
    foreach ($entry in $Snapshot.Values) {
        $entries += (ConvertTo-ProjectRegistryBackupEntry -Entry $entry)
    }
    $document = [ordered]@{
        Format = 'Microslop.RegistryBackup'
        Version = 1
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Entries = $entries
    }
    $json = ConvertTo-Json -InputObject $document -Depth 8
    $temporaryPath = $Path + '.tmp'
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        throw
    }

    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level INFO -Message ("Persistent registry backup saved ({0} entries): {1}" -f $entries.Count, $Path)
    }
    return $Path
}

function Import-ProjectRegistrySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Registry backup file not found: $Path" }
    $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($document.Format -ne 'Microslop.RegistryBackup' -or $document.Version -ne 1 -or $null -eq $document.Entries) {
        throw "Unsupported or invalid registry backup format."
    }

    $snapshot = @{}
    foreach ($item in @($document.Entries)) {
        if ([string]$item.Path -notmatch '^(HKLM|HKCU|HKCR|HKU|HKCC):\\' -or
            [string]::IsNullOrWhiteSpace([string]$item.Name) -or
            ($item.Exists -and [string]$item.ValueKind -notin @('DWord','String','ExpandString','QWord','MultiString','Binary'))) {
            throw "Registry backup contains an invalid entry."
        }
        $value = $item.Value
        if ($item.Exists -and $item.ValueKind -eq 'Binary') {
            $value = [Convert]::FromBase64String([string]$item.Value)
        } elseif ($item.Exists -and $item.ValueKind -eq 'MultiString') {
            $value = [string[]]@($item.Value)
        }
        $key = Get-ProjectRegistrySnapshotKey -Path ([string]$item.Path) -Name ([string]$item.Name)
        if ($snapshot.ContainsKey($key)) { throw "Registry backup contains duplicate entries." }
        $snapshot[$key] = @{
            Path = [string]$item.Path; Name = [string]$item.Name
            Exists = [bool]$item.Exists; Value = $value
            ValueKind = [string]$item.ValueKind
        }
    }
    return ,$snapshot
}

function Restore-ProjectRegistrySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Snapshot)

    $success = $true
    foreach ($entry in $Snapshot.Values) {
        try {
            if ($entry.Exists) {
                Set-ProjectRegistryValue -Path $entry.Path -Name $entry.Name -Value $entry.Value -ValueKind $entry.ValueKind | Out-Null
            } elseif (Test-Path -LiteralPath $entry.Path) {
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop
                if (Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue) {
                    throw "Registry value still exists after removal."
                }
            }
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                Write-ProjectLog -Level INFO -Message ("Registry snapshot restored: {0}\{1}" -f $entry.Path, $entry.Name)
            }
        } catch {
            $success = $false
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                Write-ProjectLog -Level WARNING -Message ("Could not restore registry value {0}\{1}: {2}" -f $entry.Path, $entry.Name, $_.Exception.Message)
            } else {
                Write-Warning ("Could not restore registry value {0}\{1}: {2}" -f $entry.Path, $entry.Name, $_.Exception.Message)
            }
        }
    }
    return $success
}
