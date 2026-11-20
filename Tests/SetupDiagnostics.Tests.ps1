BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/SetupDiagnostics.ps1")
}

Describe "Setup error diagnostics" {
    It "filters PowerShell error records without treating normal output as errors" {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("synthetic failure"),
            "SyntheticFailure",
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )

        $records = @(Get-ProjectErrorRecords -Output @("normal output", 42, $errorRecord))

        $records | Should -HaveCount 1
        $records[0].FullyQualifiedErrorId | Should -Be "SyntheticFailure"
    }

    It "returns an empty collection when no error records were emitted" {
        $records = @(Get-ProjectErrorRecords -Output @("normal output", 42))

        $records | Should -HaveCount 0
    }

    It "formats module name, exception type, message and error identifier" {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("synthetic failure"),
            "SyntheticFailure",
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )

        $diagnostic = Format-ProjectErrorRecord -ErrorRecord $errorRecord -ModuleName "ExampleModule.ps1"

        $diagnostic | Should -Match "Module: ExampleModule.ps1"
        $diagnostic | Should -Match "System.InvalidOperationException"
        $diagnostic | Should -Match "Message: synthetic failure"
        $diagnostic | Should -Match "FullyQualifiedErrorId: SyntheticFailure"
    }
}
