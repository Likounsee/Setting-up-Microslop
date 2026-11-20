# Registry helpers with in-memory snapshots and read-back verification.
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
    if (-not $matches) {
        throw "Registry verification failed for '$Path\$Name'."
    }

    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level INFO -Message ("Registry value verified: {0}\{1} ({2})" -f $Path, $Name, $ValueKind)
    }
    return $true
}

function Restore-ProjectRegistrySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Snapshot)

    foreach ($entry in $Snapshot.Values) {
        try {
            if ($entry.Exists) {
                New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.ValueKind -Force -ErrorAction Stop | Out-Null
            } elseif (Test-Path -LiteralPath $entry.Path) {
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
            }
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                Write-ProjectLog -Level INFO -Message ("Registry snapshot restored: {0}\{1}" -f $entry.Path, $entry.Name)
            }
        } catch {
            if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                Write-ProjectLog -Level WARNING -Message ("Could not restore registry value {0}\{1}: {2}" -f $entry.Path, $entry.Name, $_.Exception.Message)
            } else {
                Write-Warning ("Could not restore registry value {0}\{1}: {2}" -f $entry.Path, $entry.Name, $_.Exception.Message)
            }
        }
    }
}