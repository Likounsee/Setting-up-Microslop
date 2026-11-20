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

        $result = Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot

        $result | Should -BeTrue
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It "refuses a nested directory" {
        $target = Join-Path $script:packagesRoot "Parent/Child"
        New-Item -Path $target -ItemType Directory -Force | Out-Null

        $result = Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot

        $result | Should -BeFalse
        Test-Path -LiteralPath $target | Should -BeTrue
    }

    It "refuses a directory outside the approved root" {
        $outside = Join-Path $script:safetyTestRoot "Outside"
        New-Item -Path $outside -ItemType Directory -Force | Out-Null

        $result = Remove-ProjectPackageDirectory -TargetPath $outside -PackagesRoot $script:packagesRoot

        $result | Should -BeFalse
        Test-Path -LiteralPath $outside | Should -BeTrue
    }

    It "treats an already missing direct child as successfully cleaned" {
        $target = Join-Path $script:packagesRoot "AlreadyGone"

        Remove-ProjectPackageDirectory -TargetPath $target -PackagesRoot $script:packagesRoot | Should -BeTrue
    }

    It "rejects an empty target" {
        Remove-ProjectPackageDirectory -TargetPath "" -PackagesRoot $script:packagesRoot | Should -BeFalse
    }
}

Describe "Restore-ProjectServiceStates" {
    BeforeEach {
        $script:startedServices = @()
        Mock Start-Service {
            $script:startedServices += $Name
        }
    }

    It "restarts only services that were running before maintenance" {
        $wasRunning = @{ wuauserv = $true; bits = $false; dosvc = $true }

        Restore-ProjectServiceStates -WasRunning $wasRunning -ServiceNames @("wuauserv", "bits", "dosvc")

        $script:startedServices | Should -HaveCount 2
        $script:startedServices | Should -Contain "wuauserv"
        $script:startedServices | Should -Contain "dosvc"
        $script:startedServices | Should -Not -Contain "bits"
    }

    It "does not start services absent from the original-state snapshot" {
        Restore-ProjectServiceStates -WasRunning @{} -ServiceNames @("wuauserv")

        $script:startedServices | Should -HaveCount 0
    }

    It "continues when restoring one service fails" {
        Mock Start-Service {
            if ($Name -eq "wuauserv") { throw "simulated service error" }
            $script:startedServices += $Name
        }

        $wasRunning = @{ wuauserv = $true; bits = $true }
        Restore-ProjectServiceStates -WasRunning $wasRunning -ServiceNames @("wuauserv", "bits")

        $script:startedServices | Should -Contain "bits"
    }
}
