BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Logging.ps1")
    $script:testLogDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-pester-" + [guid]::NewGuid().ToString("N"))
}

AfterAll {
    if (Test-Path -LiteralPath $script:testLogDirectory) {
        Remove-Item -LiteralPath $script:testLogDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Function:\TestNativeCommandStub -ErrorAction SilentlyContinue
}

Describe "Project logging" {
    It "creates a log file and records messages" {
        $logPath = Initialize-ProjectLogging -ScriptName "UnitTest.ps1" -LogDirectory $script:testLogDirectory
        Write-ProjectLog -Level WARNING -Message "test warning"

        Test-Path -LiteralPath $logPath | Should -BeTrue
        $content = Get-Content -LiteralPath $logPath -Raw
        $content | Should -Match "\[INFO\].*Execution started"
        $content | Should -Match "\[WARNING\].*test warning"
    }

    It "rejects an unsupported log level" {
        { Write-ProjectLog -Level "TRACE" -Message "invalid" } | Should -Throw
    }
}

Describe "Invoke-ProjectNativeCommand" {
    BeforeEach {
        function TestNativeCommandStub {
            param([string]$Mode)
            if ($Mode -eq "Output") { Write-Output "stub output" }
            $global:LASTEXITCODE = [int]$script:StubExitCode
        }
        $script:StubExitCode = 0
    }

    It "returns zero and records successful output" {
        $logPath = Initialize-ProjectLogging -ScriptName "NativeSuccess.ps1" -LogDirectory $script:testLogDirectory
        $result = Invoke-ProjectNativeCommand -FilePath "TestNativeCommandStub" -ArgumentList @("Output")

        $result | Should -Be 0
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match "stub output"
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match "completed with exit code 0"
    }

    It "throws and logs a non-zero exit code by default" {
        $script:StubExitCode = 23
        $logPath = Initialize-ProjectLogging -ScriptName "NativeFailure.ps1" -LogDirectory $script:testLogDirectory

        { Invoke-ProjectNativeCommand -FilePath "TestNativeCommandStub" } | Should -Throw "*exit code 23*"
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match "\[ERROR\].*exit code 23"
    }

    It "allows selected non-zero exit codes" {
        $script:StubExitCode = 3010
        $logPath = Initialize-ProjectLogging -ScriptName "NativeAllowed.ps1" -LogDirectory $script:testLogDirectory

        $result = Invoke-ProjectNativeCommand -FilePath "TestNativeCommandStub" -AllowedExitCodes @(0, 3010)

        $result | Should -Be 3010
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match "completed with exit code 3010"
    }

    It "logs a warning and continues when ContinueOnError is set" {
        $script:StubExitCode = 5
        $logPath = Initialize-ProjectLogging -ScriptName "NativeWarning.ps1" -LogDirectory $script:testLogDirectory

        $result = Invoke-ProjectNativeCommand -FilePath "TestNativeCommandStub" -ContinueOnError

        $result | Should -Be 5
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match "\[WARNING\].*exit code 5"
    }
}
