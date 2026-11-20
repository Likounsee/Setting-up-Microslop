BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Safety.ps1")
    . (Join-Path $script:repoRoot "Common/ServiceState.ps1")
    $script:safetyTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-safety-" + [guid]::NewGuid().ToString("N"))
    $script:packagesRoot = Join-Path $script:safetyTestRoot "Packages"
    New-Item -Path $script:packagesRoot -ItemType Directory -Force | Out-Null
}

AfterAll {
    if (Test-Path -LiteralPath $script:safetyTestRoot) {
        Remove-Item -LiteralPath $script:safetyTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Remove-ProjectPackageDirectory" {
    It "removes a direct child of the approved Packages root" {
        $target = Join-Path $script:packagesRoot "Example.Package"
        New-Item -Path $target -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target "data.txt") -Value "test"

        $result = Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot -BackupDirectory (Join-Path $script:safetyTestRoot "legacy-backups")

        $result | Should -BeTrue
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It "refuses a nested directory" {
        $target = Join-Path $script:packagesRoot "Parent/Child"
        New-Item -Path $target -ItemType Directory -Force | Out-Null

        $result = Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot -BackupDirectory (Join-Path $script:safetyTestRoot "legacy-backups")

        $result | Should -BeFalse
        Test-Path -LiteralPath $target | Should -BeTrue
    }

    It "refuses a directory outside the approved root" {
        $outside = Join-Path $script:safetyTestRoot "Outside"
        New-Item -Path $outside -ItemType Directory -Force | Out-Null

        $result = Remove-ProjectPackageDirectory -TargetPath $outside -PackagesRoot $script:packagesRoot -BackupDirectory (Join-Path $script:safetyTestRoot "legacy-backups")

        $result | Should -BeFalse
        Test-Path -LiteralPath $outside | Should -BeTrue
    }

    It "treats an already missing direct child as successfully cleaned" {
        $target = Join-Path $script:packagesRoot "AlreadyGone"

        Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot -BackupDirectory (Join-Path $script:safetyTestRoot "legacy-backups") | Should -BeTrue
    }

    It "rejects an empty target" {
        Remove-ProjectPackageDirectory -TargetPath "" -PackagesRoot $script:packagesRoot -BackupDirectory (Join-Path $script:safetyTestRoot "legacy-backups") | Should -BeFalse
    }
}

Describe "Restore-ProjectServiceStates" {
    BeforeEach {
        $script:startedServices = @()
        $script:failServiceName = $null
        Mock Start-Service {
            if ($Name -eq $script:failServiceName) { throw "simulated service error" }
            $script:startedServices += $Name
        }
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = 'Stopped' } }
    }

    It "restarts only services that were running before maintenance" {
        $wasRunning = @{ wuauserv = $true; bits = $false; dosvc = $true }

        (Restore-ProjectServiceStates -WasRunning $wasRunning -ServiceNames @("wuauserv", "bits", "dosvc")) | Should -BeTrue

        $script:startedServices | Should -HaveCount 2
        $script:startedServices | Should -Contain "wuauserv"
        $script:startedServices | Should -Contain "dosvc"
        $script:startedServices | Should -Not -Contain "bits"
    }


    It "does not restart a service that is already running" {
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = 'Running' } }
        (Restore-ProjectServiceStates -WasRunning @{ wuauserv = $true } -ServiceNames @("wuauserv")) | Should -BeTrue
        Should -Invoke Start-Service -Times 0 -Exactly
    }

    It "does not start services absent from the original-state snapshot" {
        Restore-ProjectServiceStates -WasRunning @{} -ServiceNames @("wuauserv")

        $script:startedServices | Should -HaveCount 0
    }

    It "continues when restoring one service fails" {
        $script:failServiceName = "wuauserv"
        $wasRunning = @{ wuauserv = $true; bits = $true }
        (Restore-ProjectServiceStates -WasRunning $wasRunning -ServiceNames @("wuauserv", "bits")) | Should -BeFalse
        $script:startedServices | Should -Contain "bits"
    }
}


Describe "Persistent service-state backups" {
    It "saves and re-imports service states" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-services-" + [guid]::NewGuid().ToString("N") + ".json")
        $snapshot = @{ wuauserv = $true; bits = $false; dosvc = $true }
        try {
            Save-ProjectServiceSnapshot -WasRunning $snapshot -Path $backupPath | Should -Be $backupPath
            $loaded = Import-ProjectServiceSnapshot -Path $backupPath
            $loaded.Count | Should -Be 3
            $loaded["wuauserv"] | Should -BeTrue
            $loaded["bits"] | Should -BeFalse
            $loaded["dosvc"] | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects a service backup with an unsupported format" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-services-invalid-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            Set-Content -LiteralPath $backupPath -Value '{"Format":"Other","Version":99,"Services":[]}' -Encoding UTF8
            { Import-ProjectServiceSnapshot -Path $backupPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
    It "rejects invalid service names before writing a backup" {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-services-invalid-name-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            { Save-ProjectServiceSnapshot -WasRunning @{ "Bad/Service" = $true } -Path $backupPath } | Should -Throw
            Test-Path -LiteralPath $backupPath | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

}


Describe "Verified filesystem package backups" {
    BeforeEach {
        $script:fileBackupRoot = Join-Path $script:safetyTestRoot ("FileBackups-" + [guid]::NewGuid().ToString("N"))
        $script:fileBackupTarget = Join-Path $script:packagesRoot ("BackupTest-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:fileBackupTarget -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fileBackupTarget "nested") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fileBackupTarget "nested\payload.txt") -Value "recovery-data"
    }

    It "backs up, verifies, removes, and restores a package directory" {
        $backup = Backup-ProjectPackageDirectory -TargetPath $script:fileBackupTarget -PackagesRoot $script:packagesRoot -BackupDirectory $script:fileBackupRoot
        Test-Path -LiteralPath $script:fileBackupTarget | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $backup "manifest.json") | Should -BeTrue

        $restored = Restore-ProjectFileSystemBackup -BackupRoot $backup -PackagesRoot $script:packagesRoot
        $restored | Should -Be 1
        Get-Content -LiteralPath (Join-Path $script:fileBackupTarget "nested\payload.txt") -Raw | Should -Match "recovery-data"
    }

    It "does not overwrite an existing restore destination" {
        $backup = Backup-ProjectPackageDirectory -TargetPath $script:fileBackupTarget -PackagesRoot $script:packagesRoot -BackupDirectory $script:fileBackupRoot
        New-Item -ItemType Directory -Path $script:fileBackupTarget -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fileBackupTarget "keep.txt") -Value "newer-data"

        $restored = Restore-ProjectFileSystemBackup -BackupRoot $backup -PackagesRoot $script:packagesRoot -WarningAction SilentlyContinue
        $restored | Should -Be 0
        Get-Content -LiteralPath (Join-Path $script:fileBackupTarget "keep.txt") -Raw | Should -Match "newer-data"
    }

    It "rejects a backup target outside the approved Packages root" {
        $outside = Join-Path $script:safetyTestRoot "NotAPackage"
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        { Backup-ProjectPackageDirectory -TargetPath $outside -PackagesRoot $script:packagesRoot -BackupDirectory $script:fileBackupRoot } | Should -Throw
    }

    It "rejects a manifest destination outside the approved Packages root" {
        $backup = Backup-ProjectPackageDirectory -TargetPath $script:fileBackupTarget -PackagesRoot $script:packagesRoot -BackupDirectory $script:fileBackupRoot
        $manifestPath = Join-Path $backup "manifest.json"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.Entries[0].OriginalPath = Join-Path $script:safetyTestRoot "outside-target"
        Set-Content -LiteralPath $manifestPath -Value (ConvertTo-Json -InputObject $manifest -Depth 8)
        { Restore-ProjectFileSystemBackup -BackupRoot $backup -PackagesRoot $script:packagesRoot } | Should -Throw
    }

    It "rejects a tampered backup file before restoring it" {
        $backup = Backup-ProjectPackageDirectory -TargetPath $script:fileBackupTarget -PackagesRoot $script:packagesRoot -BackupDirectory $script:fileBackupRoot
        Set-Content -LiteralPath (Join-Path $backup "items/package/nested/payload.txt") -Value "tampered"
        { Restore-ProjectFileSystemBackup -BackupRoot $backup -PackagesRoot $script:packagesRoot } | Should -Throw
        Test-Path -LiteralPath $script:fileBackupTarget | Should -BeFalse
    }
}
