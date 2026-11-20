BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Registry.ps1")
    $script:testRegistryPath = "HKCU:\Software\Microslop-Pester-" + [guid]::NewGuid().ToString("N")
    $script:registrySnapshot = @{}
}

AfterAll {
    if (Test-Path -LiteralPath $script:testRegistryPath) {
        Remove-Item -LiteralPath $script:testRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Project registry helpers" {
    It "creates and verifies a DWORD registry value" {
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "Enabled" -Value 1 -ValueKind DWord -Snapshot $script:registrySnapshot | Should -BeTrue
        (Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "Enabled") | Should -Be 1
    }

    It "captures an existing value before changing it" {
        $before = @{}
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "Enabled" -Value 0 -ValueKind DWord -Snapshot $before | Should -BeTrue
        $before.Count | Should -Be 1
        @($before.Values)[0].Exists | Should -BeTrue
        @($before.Values)[0].Value | Should -Be 1
        @($before.Values)[0].ValueKind | Should -Be "DWord"
    }

    It "restores a prior value from the snapshot" {
        $snapshot = @{}
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "RestoreMe" -Value "original" -ValueKind String | Should -BeTrue
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "RestoreMe" -Value "changed" -ValueKind String -Snapshot $snapshot | Should -BeTrue
        Restore-ProjectRegistrySnapshot -Snapshot $snapshot
        (Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "RestoreMe") | Should -Be "original"
    }

    It "removes a value that did not exist before the snapshot" {
        $snapshot = @{}
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "NewOnly" -Value 7 -ValueKind DWord -Snapshot $snapshot | Should -BeTrue
        Restore-ProjectRegistrySnapshot -Snapshot $snapshot
        { Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "NewOnly" -ErrorAction Stop } | Should -Throw
    }

    It "does not put registry data values into log messages" {
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-" + [guid]::NewGuid().ToString("N") + ".log")
        . (Join-Path $script:repoRoot "Common/Logging.ps1")
        Initialize-ProjectLogging -ScriptName "RegistryTest.ps1" -LogDirectory (Split-Path -Parent $logPath) | Out-Null
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "PrivateValue" -Value "do-not-log-this" -ValueKind String | Out-Null
        (Get-Content -LiteralPath $script:ProjectLogPath -Raw) | Should -Not -Match "do-not-log-this"
        Remove-Item -LiteralPath $script:ProjectLogPath -Force -ErrorAction SilentlyContinue
    }
    It "saves a persistent backup and restores it after re-import" {
        $snapshot = @{}
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "Persistent" -Value "before" -ValueKind String | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "Persistent" -Value "script-change" -ValueKind String -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            (Test-Path -LiteralPath $backupPath -PathType Leaf) | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "Persistent" -Value "after" -ValueKind String -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeTrue
            (Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "Persistent") | Should -Be "before"
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "round-trips binary registry values through a persistent backup" {
        $snapshot = @{}
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-" + [guid]::NewGuid().ToString("N") + ".json")
        $bytes = [byte[]](1, 2, 3, 254)
        try {
            $originalBytes = [byte[]](9, 8, 7)
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "BinaryValue" -Value $originalBytes -ValueKind Binary | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "BinaryValue" -Value $bytes -ValueKind Binary -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "BinaryValue" -Value ([byte[]](4, 5, 6)) -ValueKind Binary -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeTrue
            [Convert]::ToBase64String([byte[]](Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "BinaryValue")) |
                Should -Be ([Convert]::ToBase64String($originalBytes))
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects a backup with an unsupported format" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-invalid-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            Set-Content -LiteralPath $backupPath -Value '{"Format":"Other","Version":99,"Entries":[]}' -Encoding UTF8
            { Import-ProjectRegistrySnapshot -Path $backupPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not overwrite a registry value changed after the backup unless forced" {
        $snapshot = @{}
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-conflict-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "ConflictValue" -Value "before" -ValueKind String | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "ConflictValue" -Value "script-value" -ValueKind String -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "ConflictValue" -Value "user-value" -ValueKind String | Should -BeTrue
            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeFalse
            (Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "ConflictValue") | Should -Be "user-value"
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded -Force) | Should -BeTrue
            (Get-ItemPropertyValue -LiteralPath $script:testRegistryPath -Name "ConflictValue") | Should -Be "before"
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "removes a registry key that the module created when rolling back its only value" {
        $newKeyPath = "HKCU:\Software\Microslop-Pester-NewKey-" + [guid]::NewGuid().ToString("N")
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-newkey-" + [guid]::NewGuid().ToString("N") + ".json")
        $snapshot = @{}
        try {
            Set-ProjectRegistryValue -Path $newKeyPath -Name "Temporary" -Value 1 -ValueKind DWord -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            (Test-Path -LiteralPath $newKeyPath) | Should -BeTrue
            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeTrue
            (Test-Path -LiteralPath $newKeyPath) | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $newKeyPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "backs up and restores a complete registry key tree including nested and default values" {
        $treePath = $script:testRegistryPath + "\Tree-" + [guid]::NewGuid().ToString("N")
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-tree-" + [guid]::NewGuid().ToString("N") + ".json")
        $nestedPath = Join-Path $treePath "Nested\Child"
        $snapshot = @{}
        try {
            New-Item -Path $nestedPath -Force | Out-Null
            $rootKey = Get-Item -LiteralPath $treePath
            try { $rootKey.SetValue("", "root-default", [Microsoft.Win32.RegistryValueKind]::String) } finally { $rootKey.Dispose() }
            Set-ProjectRegistryValue -Path $nestedPath -Name "Payload" -Value ([byte[]](3, 2, 1)) -ValueKind Binary | Should -BeTrue

            Remove-ProjectRegistryKeyTree -Path $treePath -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            (Test-Path -LiteralPath $treePath) | Should -BeFalse

            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeTrue
            (Test-Path -LiteralPath $nestedPath) | Should -BeTrue
            $restoredRoot = Get-Item -LiteralPath $treePath
            try { $restoredRoot.GetValue("") | Should -Be "root-default" } finally { $restoredRoot.Dispose() }
            $restoredChild = Get-Item -LiteralPath $nestedPath
            try {
                [Convert]::ToBase64String([byte[]]$restoredChild.GetValue("Payload")) | Should -Be ([Convert]::ToBase64String([byte[]](3, 2, 1)))
            } finally { $restoredChild.Dispose() }
        } finally {
            Remove-Item -LiteralPath $treePath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not overwrite a registry key tree recreated after deletion" {
        $treePath = $script:testRegistryPath + "\ConflictTree-" + [guid]::NewGuid().ToString("N")
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-tree-conflict-" + [guid]::NewGuid().ToString("N") + ".json")
        $snapshot = @{}
        try {
            New-Item -Path $treePath -Force | Out-Null
            Set-ProjectRegistryValue -Path $treePath -Name "Original" -Value "old" -ValueKind String | Out-Null
            Remove-ProjectRegistryKeyTree -Path $treePath -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue
            New-Item -Path $treePath -Force | Out-Null
            Set-ProjectRegistryValue -Path $treePath -Name "Newer" -Value "keep" -ValueKind String | Out-Null

            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded) | Should -BeFalse
            (Get-ItemPropertyValue -LiteralPath $treePath -Name "Newer") | Should -Be "keep"
        } finally {
            Remove-Item -LiteralPath $treePath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects registry backup paths that attempt to escape their hive" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-unsafe-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            $document = @{
                Format = "Microslop.RegistryBackup"
                Version = 3
                Entries = @()
                KeyTrees = @(@{
                    Path = "HKCU:\\Software\\..\\Run"
                    ExpectedAbsent = $true
                    Nodes = @(@{ RelativePath = ""; Values = @() })
                })
            }
            $document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath
            { Import-ProjectRegistrySnapshot -Path $backupPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects registry key-tree relative paths that escape the backed-up root" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-unsafe-tree-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            $document = @{
                Format = "Microslop.RegistryBackup"
                Version = 3
                Entries = @()
                KeyTrees = @(@{
                    Path = $script:testRegistryPath
                    ExpectedAbsent = $true
                    Nodes = @(
                        @{ RelativePath = ""; Values = @() },
                        @{ RelativePath = "..\\OtherKey"; Values = @() }
                    )
                })
            }
            $document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $backupPath
            { Import-ProjectRegistrySnapshot -Path $backupPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "replaces a recreated registry key tree only when Force is supplied" {
        $treePath = $script:testRegistryPath + "\\ForceTree-" + [guid]::NewGuid().ToString("N")
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-registry-tree-force-" + [guid]::NewGuid().ToString("N") + ".json")
        $snapshot = @{}
        try {
            New-Item -Path $treePath -Force | Out-Null
            Set-ProjectRegistryValue -Path $treePath -Name "Original" -Value "backup" -ValueKind String | Out-Null
            Remove-ProjectRegistryKeyTree -Path $treePath -Snapshot $snapshot -BackupFile $backupPath | Should -BeTrue

            New-Item -Path $treePath -Force | Out-Null
            Set-ProjectRegistryValue -Path $treePath -Name "Newer" -Value "replace-me" -ValueKind String | Out-Null
            $loaded = Import-ProjectRegistrySnapshot -Path $backupPath
            (Restore-ProjectRegistrySnapshot -Snapshot $loaded -Force) | Should -BeTrue
            (Get-ItemPropertyValue -LiteralPath $treePath -Name "Original") | Should -Be "backup"
            (Get-ItemProperty -LiteralPath $treePath -Name "Newer" -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        } finally {
            Remove-Item -LiteralPath $treePath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

}