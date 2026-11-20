BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Logging.ps1")
    . (Join-Path $script:repoRoot "Common/OperationJournal.ps1")
    . (Join-Path $script:repoRoot "Common/TemporaryCleanup.ps1")
    $script:journalTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-journal-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:journalTestRoot -Force | Out-Null
}
AfterAll {
    if (Test-Path -LiteralPath $script:journalTestRoot) {
        Remove-Item -LiteralPath $script:journalTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Function:\TestJournalNativeStub -ErrorAction SilentlyContinue
}

Describe "Persistent operation journal" {
    It "creates and appends timestamped operation records" {
        $path = Join-Path $script:journalTestRoot "operations.json"
        Write-ProjectOperationRecord -JournalPath $path -Operation "Test cleanup" -Category Regenerable -Status Started -Target "C:\Temp\example"
        Write-ProjectOperationRecord -JournalPath $path -Operation "Test cleanup" -Category Regenerable -Status Completed -Target "C:\Temp\example" -ExitCode 0
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $doc.Format | Should -Be "Microslop.OperationJournal"
        @($doc.Records) | Should -HaveCount 2
        $doc.Records[0].Status | Should -Be "Started"
        $doc.Records[1].ExitCode | Should -Be 0
    }

    It "rejects an unsupported journal format" {
        $path = Join-Path $script:journalTestRoot "invalid.json"
        Set-Content -LiteralPath $path -Value '{"Format":"Other","Version":1,"Records":[]}'
        { Write-ProjectOperationRecord -JournalPath $path -Operation "test" -Category Informational -Status Started } | Should -Throw
    }

    It "rejects oversized operation details" {
        $path = Join-Path $script:journalTestRoot "oversized.json"
        { Write-ProjectOperationRecord -JournalPath $path -Operation "test" -Category Informational -Status Started -Details ("x" * 4097) } | Should -Throw
    }

    It "tracks successful native command start and completion" {
        function TestJournalNativeStub {
            $global:LASTEXITCODE = 0
        }
        $path = Join-Path $script:journalTestRoot "native-success.json"
        $result = Invoke-ProjectTrackedNativeCommand -FilePath "TestJournalNativeStub" -Operation "Native test" -Category Regenerable -JournalPath $path
        $result | Should -Be 0
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        @($doc.Records) | Should -HaveCount 2
        $doc.Records[0].Status | Should -Be "Started"
        $doc.Records[1].Status | Should -Be "Completed"
    }

    It "tracks native command failures" {
        function TestJournalNativeStub {
            $global:LASTEXITCODE = 42
        }
        $path = Join-Path $script:journalTestRoot "native-failure.json"
        { Invoke-ProjectTrackedNativeCommand -FilePath "TestJournalNativeStub" -Operation "Native failure" -Category Irreversible -JournalPath $path } | Should -Throw
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $doc.Records[-1].Status | Should -Be "Failed"
        $doc.Records[-1].ExitCode | Should -Be 42
    }
}

Describe "Age-limited temporary cleanup" {
    BeforeEach {
        $script:tempRoot = Join-Path $script:journalTestRoot ("temp-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        $script:tempJournal = Join-Path $script:tempRoot "operations.json"
    }

    It "removes only entries older than the configured threshold" {
        $old = Join-Path $script:tempRoot "old.tmp"
        $fresh = Join-Path $script:tempRoot "fresh.tmp"
        Set-Content -LiteralPath $old -Value "old"
        Set-Content -LiteralPath $fresh -Value "fresh"
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-10)
        $result = Remove-ProjectStaleTemporaryItems -Path $script:tempRoot -AllowedPaths @($script:tempRoot) -JournalPath $script:tempJournal -MinimumAgeDays 7
        $result.Removed | Should -Be 1
        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $fresh | Should -BeTrue
    }

    It "refuses a directory not in the explicit allowlist" {
        { Remove-ProjectStaleTemporaryItems -Path $script:tempRoot -AllowedPaths @((Join-Path $script:tempRoot "other")) -JournalPath $script:tempJournal } | Should -Throw
    }

    It "does not remove a directory containing newer nested data" {
        $nested = Join-Path $script:tempRoot "old-folder"
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        $payload = Join-Path $nested "new-file.tmp"
        Set-Content -LiteralPath $payload -Value "keep"
        (Get-Item -LiteralPath $nested).LastWriteTime = (Get-Date).AddDays(-10)
        $result = Remove-ProjectStaleTemporaryItems -Path $script:tempRoot -AllowedPaths @($script:tempRoot) -JournalPath $script:tempJournal -MinimumAgeDays 7
        $result.Skipped | Should -Be 1
        Test-Path -LiteralPath $payload | Should -BeTrue
    }

    It "records cleanup decisions in the journal" {
        $fresh = Join-Path $script:tempRoot "fresh.tmp"
        Set-Content -LiteralPath $fresh -Value "keep"
        Remove-ProjectStaleTemporaryItems -Path $script:tempRoot -AllowedPaths @($script:tempRoot) -JournalPath $script:tempJournal -MinimumAgeDays 7 | Out-Null
        $doc = Get-Content -LiteralPath $script:tempJournal -Raw | ConvertFrom-Json
        $doc.Records[0].Status | Should -Be "Skipped"
    }
}
