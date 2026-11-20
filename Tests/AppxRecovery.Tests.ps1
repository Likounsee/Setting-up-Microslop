BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot "Common/Logging.ps1")
    . (Join-Path $script:repoRoot "Common/OperationJournal.ps1")
    . (Join-Path $script:repoRoot "Common/AppxRecovery.ps1")
    $script:appxTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("microslop-appx-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:appxTestRoot -Force | Out-Null
}
AfterAll {
    if (Test-Path -LiteralPath $script:appxTestRoot) {
        Remove-Item -LiteralPath $script:appxTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Function:\Remove-AppxPackage -ErrorAction SilentlyContinue
    Remove-Item Function:\Remove-AppxProvisionedPackage -ErrorAction SilentlyContinue
}

Describe "Appx inventory and recovery planning" {
    It "saves package identities and selected metadata to a versioned inventory" {
        $path = Join-Path $script:appxTestRoot "inventory.json"
        $installed = @([pscustomobject]@{ Name="Contoso.App"; PackageFullName="Contoso.App_1.0_x64__abc"; PackageFamilyName="Contoso.App_abc"; Version="1.0"; InstallLocation="C:\Apps\Contoso"; NonRemovable=$false })
        $provisioned = @([pscustomobject]@{ DisplayName="Contoso.App"; PackageName="Contoso.App_1.0_x64__abc"; Version="1.0"; Architecture="x64" })
        Save-ProjectAppxInventory -InstalledPackages $installed -ProvisionedPackages $provisioned -Path $path | Should -Be $path
        $inventory = Import-ProjectAppxInventory -Path $path
        $inventory.Format | Should -Be "Microslop.AppxInventory"
        $inventory.InstalledPackages[0].PackageFullName | Should -Be "Contoso.App_1.0_x64__abc"
        $inventory.ProvisionedPackages[0].PackageName | Should -Be "Contoso.App_1.0_x64__abc"
        $inventory.RecoveryNote | Should -Match "does not contain package binaries"
    }

    It "rejects an unsupported inventory format" {
        $path = Join-Path $script:appxTestRoot "invalid.json"
        Set-Content -LiteralPath $path -Value '{"Format":"Other","Version":1,"InstalledPackages":[],"ProvisionedPackages":[]}'
        { Import-ProjectAppxInventory -Path $path } | Should -Throw
    }

    It "rejects inventory entries without a stable package identity" {
        $path = Join-Path $script:appxTestRoot "bad-identity.json"
        Set-Content -LiteralPath $path -Value '{"Format":"Microslop.AppxInventory","Version":1,"InstalledPackages":[{"Name":"Broken"}],"ProvisionedPackages":[]}'
        { Import-ProjectAppxInventory -Path $path } | Should -Throw
    }

    It "identifies packages missing since the inventory and suggests safe recovery routes" {
        $inventory = [pscustomobject]@{
            InstalledPackages = @(
                [pscustomobject]@{ Name="Present"; PackageFullName="Present_1.0_x64__a"; InstallLocation="" },
                [pscustomobject]@{ Name="Removed"; PackageFullName="Removed_1.0_x64__b"; InstallLocation="" }
            )
            ProvisionedPackages = @([pscustomobject]@{ DisplayName="ProvisionedRemoved"; PackageName="ProvisionedRemoved_1.0_x64__c" })
        }
        $currentInstalled = @([pscustomobject]@{ PackageFullName="Present_1.0_x64__a" })
        $plan = @(Get-ProjectAppxRecoveryPlan -Inventory $inventory -CurrentInstalledPackages $currentInstalled -CurrentProvisionedPackages @())
        $plan | Should -HaveCount 3
        ($plan | Where-Object { $_.Name -eq "Present" }).PresentNow | Should -BeTrue
        ($plan | Where-Object { $_.Name -eq "Removed" }).PresentNow | Should -BeFalse
        ($plan | Where-Object { $_.Name -eq "Removed" }).RecoveryHint | Should -Match "Microsoft Store"
        ($plan | Where-Object { $_.Name -eq "ProvisionedRemoved" }).RecoveryHint | Should -Match "installation media"
    }

    It "suggests manifest inspection only when the original install location still exists" {
        $folder = Join-Path $script:appxTestRoot "installed-package"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $inventory = [pscustomobject]@{
            InstalledPackages = @([pscustomobject]@{ Name="Recoverable"; PackageFullName="Recoverable_1.0_x64__a"; InstallLocation=$folder })
            ProvisionedPackages = @()
        }
        $plan = @(Get-ProjectAppxRecoveryPlan -Inventory $inventory -CurrentInstalledPackages @() -CurrentProvisionedPackages @())
        $plan[0].OriginalInstallLocationExists | Should -BeTrue
        $plan[0].RecoveryHint | Should -Match "AppxManifest"
    }

    It "journals successful installed-package removal" {
        function Remove-AppxPackage { param($Package, [switch]$AllUsers, $ErrorAction) $script:removedPackage = $Package }
        $journal = Join-Path $script:appxTestRoot "removal.json"
        $package = [pscustomobject]@{ PackageFullName="Contoso.App_1.0_x64__abc" }
        Invoke-ProjectAppxPackageRemoval -Package $package -PackageType Installed -JournalPath $journal | Should -BeTrue
        $script:removedPackage | Should -Be "Contoso.App_1.0_x64__abc"
        $records = (Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json).Records
        $records[0].Status | Should -Be "Started"
        $records[1].Status | Should -Be "Completed"
        $records[1].Category | Should -Be "Irreversible"
    }

    It "journals failed provisioned-package removal without hiding the failure" {
        function Remove-AppxProvisionedPackage { param($Online, $PackageName, $ErrorAction) throw "simulated package failure" }
        $journal = Join-Path $script:appxTestRoot "failed-removal.json"
        $package = [pscustomobject]@{ PackageName="Contoso.App_1.0_x64__abc" }
        Invoke-ProjectAppxPackageRemoval -Package $package -PackageType Provisioned -JournalPath $journal | Should -BeFalse
        $records = (Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json).Records
        $records[-1].Status | Should -Be "Failed"
        $records[-1].Target | Should -Be "Contoso.App_1.0_x64__abc"
    }
}
