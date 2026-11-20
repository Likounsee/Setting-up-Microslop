BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Registry.ps1")
    $script:testRegistryPath = "HKCU:\\Software\\Microslop-Pester-" + [guid]::NewGuid().ToString("N")
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
        Set-ProjectRegistryValue -Path $script:testRegistryPath -Name "RestoreMe" -Value "original" -ValueKind String -Snapshot $snapshot | Should -BeTrue
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
}