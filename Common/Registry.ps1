# Registry helpers with in-memory snapshots, persistent backups and read-back verification.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Test-ProjectRegistryPath {
    param([string]$Path, [switch]$AllowHiveRoot)
    if ($Path -notmatch '^(HKLM|HKCU|HKCR|HKU|HKCC):\\(.*)$') { return $false }
    $subPath = [string]$matches[2]
    if ([string]::IsNullOrEmpty($subPath)) { return [bool]$AllowHiveRoot }
    foreach ($segment in $subPath.Split([char]'\')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..' -or $segment.Contains([char]0)) {
            return $false
        }
    }
    return $true
}

function Test-ProjectRegistryRelativePath {
    param([string]$RelativePath)
    if ([string]::IsNullOrEmpty($RelativePath)) { return $true }
    if ($RelativePath.StartsWith('\') -or $RelativePath.EndsWith('\')) { return $false }
    foreach ($segment in $RelativePath.Split([char]'\')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..' -or $segment.Contains([char]0)) {
            return $false
        }
    }
    return $true
}

function Get-ProjectRegistrySnapshotKey {
    param([string]$Path, [string]$Name)
    return ($Path.TrimEnd('\') + '|' + $Name)
}


function Set-ProjectRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value,
        [ValidateSet('DWord', 'String', 'ExpandString', 'QWord', 'MultiString', 'Binary', 'None')]
        [string]$ValueKind = 'DWord',
        [hashtable]$Snapshot,
        [string]$BackupFile
    )

    $keyExisted = Test-Path -LiteralPath $Path
    $snapshotKey = Get-ProjectRegistrySnapshotKey -Path $Path -Name $Name
    if (($null -ne $Snapshot) -and -not $Snapshot.ContainsKey($snapshotKey)) {
        $exists = $false
        $oldValue = $null
        $oldKind = $null
        $providerPath = $Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
        $key = $null
        if ($keyExisted) {
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
        }
        $Snapshot[$snapshotKey] = @{
            Path = $Path; Name = $Name; KeyExisted = $keyExisted; Exists = $exists
            Value = $oldValue; ValueKind = $oldKind
        }
    }

    if ($null -ne $Snapshot -and $Snapshot.ContainsKey($snapshotKey)) {
        $Snapshot[$snapshotKey].CurrentValue = $Value
        $Snapshot[$snapshotKey].CurrentValueKind = $ValueKind
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupFile)) {
        Save-ProjectRegistrySnapshot -Snapshot $Snapshot -Path $BackupFile | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    if (-not (Test-ProjectRegistryPath -Path $Path)) {
        throw "Unsupported or unsafe registry path for writing: $Path"
    }
    $pathMatch = [regex]::Match($Path, '^(HKLM|HKCU|HKCR|HKU|HKCC):\\(.+)$')
    if (-not $pathMatch.Success) { throw "Unsupported registry path: $Path" }
    $hiveName = $pathMatch.Groups[1].Value
    $subKeyPath = $pathMatch.Groups[2].Value
    $hiveName = $matches[1]
    $subKeyPath = $matches[2]
    $registryBaseKey = switch ($hiveName) {
        'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
        'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
        'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
        'HKU'  { [Microsoft.Win32.Registry]::Users }
        'HKCC' { [Microsoft.Win32.Registry]::CurrentConfig }
    }
    $writeKey = $registryBaseKey.CreateSubKey($subKeyPath)
    if ($null -eq $writeKey) { throw "Could not open registry key for writing: $Path" }
    try {
        $registryKind = [System.Enum]::Parse([Microsoft.Win32.RegistryValueKind], $ValueKind, $true)
        $writeKey.SetValue($Name, $Value, $registryKind)
        $writeKey.Flush()
    } finally {
        $writeKey.Dispose()
    }
    $providerPath = $Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
    $verifyKey = Get-Item -LiteralPath $providerPath -ErrorAction Stop
    try {
        $actualKind = [string]$verifyKey.GetValueKind($Name)
        $actual = $verifyKey.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally {
        if ($verifyKey -is [System.IDisposable]) { $verifyKey.Dispose() }
    }
    if ($actualKind -ne $ValueKind) { throw "Registry type verification failed for '$Path\$Name'." }
    if ($ValueKind -eq 'Binary' -or $ValueKind -eq 'MultiString' -or $ValueKind -eq 'None') {
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


function ConvertTo-ProjectRegistrySerializedValue {
    param([object]$Value, [string]$ValueKind)
    if ($ValueKind -eq 'Binary' -or $ValueKind -eq 'None') { return [Convert]::ToBase64String([byte[]]$Value) }
    if ($ValueKind -eq 'MultiString') { return ,([string[]]$Value) }
    return $Value
}

function ConvertFrom-ProjectRegistrySerializedValue {
    param([object]$Value, [string]$ValueKind)
    if ($ValueKind -eq 'Binary' -or $ValueKind -eq 'None') { return ,([Convert]::FromBase64String([string]$Value)) }
    if ($ValueKind -eq 'MultiString') { return ,([string[]]@($Value)) }
    return $Value
}

function Remove-ProjectRegistryKeyTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Snapshot,
        [Parameter(Mandatory = $true)][string]$BackupFile
    )

    if (-not (Test-ProjectRegistryPath -Path $Path)) {
        throw "Registry key-tree path is outside supported registry hives or contains an unsafe path segment."
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $providerPath = $Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
    $rootKey = Get-Item -LiteralPath $providerPath -ErrorAction Stop
    $tree = New-Object System.Collections.ArrayList
    function Add-RegistryTreeNode {
        param([Microsoft.Win32.RegistryKey]$Key, [string]$RelativePath)
        $values = @()
        foreach ($valueName in $Key.GetValueNames()) {
            $kind = [string]$Key.GetValueKind($valueName)
            if ($kind -notin @('DWord','String','ExpandString','QWord','MultiString','Binary','None')) {
                throw "Unsupported registry value type '$kind' in key tree '$Path'; the tree was not removed."
            }
            $raw = $Key.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $values += [ordered]@{
                Name = [string]$valueName
                Kind = $kind
                Value = $raw
            }
        }
        $treeNode = [ordered]@{ RelativePath = $RelativePath; Values = $values }
        $null = $tree.Add($treeNode)
        foreach ($subName in $Key.GetSubKeyNames()) {
            $child = $Key.OpenSubKey($subName, $false)
            if ($null -ne $child) {
                try {
                    $childRelative = if ([string]::IsNullOrEmpty($RelativePath)) { $subName } else { $RelativePath + '\' + $subName }
                    Add-RegistryTreeNode -Key $child -RelativePath $childRelative
                } finally { $child.Dispose() }
            }
        }
    }
    try {
        Add-RegistryTreeNode -Key $rootKey -RelativePath ''
    } finally {
        if ($rootKey -is [System.IDisposable]) { $rootKey.Dispose() }
    }

    $snapshotKey = '__KEYTREE__|' + $Path
    if ($Snapshot.ContainsKey($snapshotKey)) { throw "Registry key tree already captured in this run: $Path" }
    $Snapshot[$snapshotKey] = @{ Kind = 'KeyTree'; Path = $Path; Tree = $tree.ToArray() }
    Save-ProjectRegistrySnapshot -Snapshot $Snapshot -Path $BackupFile | Out-Null

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Path) { throw "Registry key tree still exists after removal: $Path" }
    } catch {
        $restoreSnapshot = @{ $snapshotKey = $Snapshot[$snapshotKey] }
        $recovered = Restore-ProjectRegistrySnapshot -Snapshot $restoreSnapshot -Force
        if (-not $recovered) {
            throw "Registry key-tree removal failed and automatic recovery was incomplete. Backup: $BackupFile. Original error: $($_.Exception.Message)"
        }
        throw
    }
    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level INFO -Message ("Registry key tree removed and backed up: {0}" -f $Path)
    }
    return $true
}

function ConvertTo-ProjectRegistryBackupEntry {
    param([Parameter(Mandatory = $true)][hashtable]$Entry)

    $serializedValue = $Entry.Value
    if ($Entry.Exists -and ($Entry.ValueKind -eq 'Binary' -or $Entry.ValueKind -eq 'None')) {
        $serializedValue = [Convert]::ToBase64String([byte[]]$Entry.Value)
    } elseif ($Entry.Exists -and $Entry.ValueKind -eq 'MultiString') {
        $serializedValue = @($Entry.Value)
    }
    $expectedValue = $Entry.CurrentValue
    if ($null -ne $Entry.CurrentValueKind -and ($Entry.CurrentValueKind -eq 'Binary' -or $Entry.CurrentValueKind -eq 'None')) {
        $expectedValue = [Convert]::ToBase64String([byte[]]$Entry.CurrentValue)
    } elseif ($null -ne $Entry.CurrentValueKind -and $Entry.CurrentValueKind -eq 'MultiString') {
        $expectedValue = @($Entry.CurrentValue)
    }
    return [ordered]@{
        Path = [string]$Entry.Path
        Name = [string]$Entry.Name
        KeyExisted = if ($null -eq $Entry.KeyExisted) { $true } else { [bool]$Entry.KeyExisted }
        Exists = [bool]$Entry.Exists
        ValueKind = $Entry.ValueKind
        Value = $serializedValue
        ExpectedExists = ($null -ne $Entry.CurrentValueKind)
        ExpectedValueKind = $Entry.CurrentValueKind
        ExpectedValue = $expectedValue
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
    $keyTrees = @()
    foreach ($entry in $Snapshot.Values) {
        if ($entry.Kind -eq 'KeyTree') {
            $serializedNodes = @()
            foreach ($node in $entry.Tree) {
                $serializedValues = @()
                foreach ($value in $node.Values) {
                    $serializedValues += [ordered]@{
                        Name = $value.Name; Kind = $value.Kind
                        Value = ConvertTo-ProjectRegistrySerializedValue -Value $value.Value -ValueKind $value.Kind
                    }
                }
                $serializedNodes += [ordered]@{ RelativePath = $node.RelativePath; Values = $serializedValues }
            }
            $keyTrees += [ordered]@{ Path = $entry.Path; Nodes = $serializedNodes; ExpectedAbsent = $true }
        } else {
            $entries += (ConvertTo-ProjectRegistryBackupEntry -Entry $entry)
        }
    }
    $document = [ordered]@{
        Format = 'Microslop.RegistryBackup'
        Version = 3
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Entries = $entries
        KeyTrees = $keyTrees
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
    if ($document.Format -ne 'Microslop.RegistryBackup' -or $document.Version -notin @(1, 2, 3) -or $null -eq $document.Entries) {
        throw "Unsupported or invalid registry backup format."
    }

    $snapshot = @{}
    foreach ($item in @($document.Entries)) {
        if (-not (Test-ProjectRegistryPath -Path ([string]$item.Path)) -or
            $null -eq $item.Name -or
            ($item.Exists -and [string]$item.ValueKind -notin @('DWord','String','ExpandString','QWord','MultiString','Binary','None'))) {
            throw "Registry backup contains an invalid entry."
        }
        $value = $item.Value
        if ($item.Exists -and ($item.ValueKind -eq 'Binary' -or $item.ValueKind -eq 'None')) {
            $value = [Convert]::FromBase64String([string]$item.Value)
        } elseif ($item.Exists -and $item.ValueKind -eq 'MultiString') {
            $value = [string[]]@($item.Value)
        }
        $key = Get-ProjectRegistrySnapshotKey -Path ([string]$item.Path) -Name ([string]$item.Name)
        if ($snapshot.ContainsKey($key)) { throw "Registry backup contains duplicate entries." }
        $entry = @{
            Path = [string]$item.Path; Name = [string]$item.Name
            KeyExisted = if ($null -eq $item.KeyExisted) { $true } else { [bool]$item.KeyExisted }
            Exists = [bool]$item.Exists; Value = $value
            ValueKind = [string]$item.ValueKind
        }
        if ($document.Version -ge 2 -and $item.ExpectedExists) {
            $expected = $item.ExpectedValue
            if ($item.ExpectedValueKind -eq 'Binary' -or $item.ExpectedValueKind -eq 'None') {
                $expected = [Convert]::FromBase64String([string]$item.ExpectedValue)
            } elseif ($item.ExpectedValueKind -eq 'MultiString') {
                $expected = [string[]]@($item.ExpectedValue)
            }
            $entry.CurrentValue = $expected
            $entry.CurrentValueKind = [string]$item.ExpectedValueKind
        }
        $snapshot[$key] = $entry
    }
    if ($document.Version -ge 3) {
        foreach ($treeItem in @($document.KeyTrees)) {
            if (-not (Test-ProjectRegistryPath -Path ([string]$treeItem.Path)) -or $null -eq $treeItem.Nodes) {
                throw "Registry backup contains an invalid key-tree entry."
            }
            $nodes = @()
            $seenRelativePaths = @{}
            foreach ($node in @($treeItem.Nodes)) {
                $relativePath = [string]$node.RelativePath
                if (-not (Test-ProjectRegistryRelativePath -RelativePath $relativePath) -or $seenRelativePaths.ContainsKey($relativePath)) {
                    throw "Registry backup contains an unsafe or duplicate key-tree path."
                }
                $seenRelativePaths[$relativePath] = $true
                $nodeValues = @()
                foreach ($value in @($node.Values)) {
                    if ([string]$value.Kind -notin @('DWord','String','ExpandString','QWord','MultiString','Binary','None') -or $null -eq $value.Name) {
                        throw "Registry key-tree backup contains an invalid value name or unsupported value kind."
                    }
                    $nodeValues += @{
                        Name = [string]$value.Name; Kind = [string]$value.Kind
                        Value = ConvertFrom-ProjectRegistrySerializedValue -Value $value.Value -ValueKind $value.Kind
                    }
                }
                $nodes += @{ RelativePath = [string]$node.RelativePath; Values = $nodeValues }
            }
            if (-not $seenRelativePaths.ContainsKey('')) {
                throw "Registry key-tree backup does not contain its root key."
            }
            $treeKey = '__KEYTREE__|' + [string]$treeItem.Path
            if ($snapshot.ContainsKey($treeKey)) { throw "Registry backup contains duplicate key trees." }
            $snapshot[$treeKey] = @{ Kind = 'KeyTree'; Path = [string]$treeItem.Path; Tree = $nodes; ExpectedAbsent = [bool]$treeItem.ExpectedAbsent }
        }
    }
    return ,$snapshot
}

function Restore-ProjectRegistrySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Snapshot,
        [switch]$Force
    )

    $success = $true
    foreach ($entry in $Snapshot.Values) {
        try {
            if ($entry.Kind -eq 'KeyTree') {
                if (Test-Path -LiteralPath $entry.Path) {
                    if (-not $Force) {
                        throw "Registry key tree exists since backup; restore skipped to avoid overwriting newer data."
                    }
                    Remove-Item -LiteralPath $entry.Path -Recurse -Force -ErrorAction Stop
                }
                foreach ($node in @($entry.Tree | Sort-Object { ([string]$_.RelativePath).Split([char]'\').Count })) {
                    $targetPath = if ([string]::IsNullOrEmpty($node.RelativePath)) { $entry.Path } else { $entry.Path.TrimEnd('\') + '\' + $node.RelativePath }
                    if (-not (Test-Path -LiteralPath $targetPath)) {
                        New-Item -Path $targetPath -Force -ErrorAction Stop | Out-Null
                    }
                    foreach ($value in @($node.Values)) {
                        Set-ProjectRegistryValue -Path $targetPath -Name $value.Name -Value $value.Value -ValueKind $value.Kind | Out-Null
                    }
                }
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                    Write-ProjectLog -Level INFO -Message ("Registry key tree restored: {0}" -f $entry.Path)
                }
                continue
            }
            if ($null -ne $entry.CurrentValueKind -and -not $Force) {
                $providerPath = $entry.Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
                $currentKey = Get-Item -LiteralPath $providerPath -ErrorAction Stop
                try {
                    $currentlyExists = $currentKey.GetValueNames() -contains $entry.Name
                    if (-not $currentlyExists) { throw "Registry value changed since backup; restore skipped." }
                    $currentKind = [string]$currentKey.GetValueKind($entry.Name)
                    $currentValue = $currentKey.GetValue($entry.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                } finally {
                    if ($currentKey -is [System.IDisposable]) { $currentKey.Dispose() }
                }
                $expectedValue = $entry.CurrentValue
                if ($currentKind -ne $entry.CurrentValueKind) { throw "Registry value type changed since backup; restore skipped." }
                if ($currentKind -eq 'Binary' -or $currentKind -eq 'MultiString' -or $currentKind -eq 'None') {
                    $unchanged = [System.Linq.Enumerable]::SequenceEqual([object[]]$currentValue, [object[]]$expectedValue)
                } else {
                    $unchanged = ($currentValue -eq $expectedValue)
                }
                if (-not $unchanged) { throw "Registry value changed since backup; restore skipped." }
            }
            if ($entry.Exists) {
                Set-ProjectRegistryValue -Path $entry.Path -Name $entry.Name -Value $entry.Value -ValueKind $entry.ValueKind | Out-Null
            } elseif (Test-Path -LiteralPath $entry.Path) {
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop
                $providerPath = $entry.Path -replace '^HKLM:', 'Registry::HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'Registry::HKEY_CURRENT_USER' -replace '^HKCR:', 'Registry::HKEY_CLASSES_ROOT' -replace '^HKU:', 'Registry::HKEY_USERS' -replace '^HKCC:', 'Registry::HKEY_CURRENT_CONFIG'
                $registryKey = Get-Item -LiteralPath $providerPath -ErrorAction Stop
                try {
                    if ($registryKey.GetValueNames() -contains $entry.Name) {
                        throw "Registry value still exists after removal."
                    }
                    $keyIsEmpty = ($registryKey.GetValueNames().Count -eq 0 -and $registryKey.GetSubKeyNames().Count -eq 0)
                } finally {
                    if ($registryKey -is [System.IDisposable]) { $registryKey.Dispose() }
                }
                if (-not $entry.KeyExisted -and $keyIsEmpty) {
                    Remove-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
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
