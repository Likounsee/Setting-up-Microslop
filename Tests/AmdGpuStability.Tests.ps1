BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/AmdGpuStability.ps1")
}

Describe "AMD GPU stability helpers" {
    It "detects only active AMD PCI display adapters" {
        Mock Get-PnpDevice {
            @(
                [pscustomobject]@{ FriendlyName = "AMD Radeon"; InstanceId = "PCI\VEN_1002&DEV_1234" },
                [pscustomobject]@{ FriendlyName = "NVIDIA GPU"; InstanceId = "PCI\VEN_10DE&DEV_5678" }
            )
        }

        $devices = @(Get-ProjectAmdDisplayDevices)

        $devices.Count | Should -Be 1
        $devices[0].FriendlyName | Should -Be "AMD Radeon"
        Should -Invoke Get-PnpDevice -Times 1 -Exactly -ParameterFilter {
            $Class -eq "Display" -and $Status -eq "OK"
        }
    }

    It "returns no devices when the system has no AMD display adapter" {
        Mock Get-PnpDevice {
            [pscustomobject]@{ FriendlyName = "Intel Graphics"; InstanceId = "PCI\VEN_8086&DEV_1234" }
        }

        @(Get-ProjectAmdDisplayDevices).Count | Should -Be 0
    }
}
