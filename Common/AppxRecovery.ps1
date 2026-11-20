# Appx inventory and auditable removal helpers.
# Inventories preserve package identity and installation metadata, not package binaries.

function Get-ProjectObjectPropertyValue {
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Save-ProjectAppxInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$InstalledPackages,
        [Parameter(Mandatory = $true)][object[]]$ProvisionedPackages,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $installedFields = @("Name", "PackageFullName", "PackageFamilyName", "Version", "Architecture", "Publisher", "PublisherId", "InstallLocation", "IsFramework", "IsResourcePackage", "IsBundle", "NonRemovable", "SignatureKind", "Status")
    $provisionedFields = @("DisplayName", "PackageName", "Version", "Architecture", "PublisherId", "ResourceId", "InstallLocation", "Regions", "CustomData")
    $installed = @(
        foreach ($package in $InstalledPackages) {
            $entry = [ordered]@{}
            foreach ($field in $installedFields) {
                $value = Get-ProjectObjectPropertyValue -InputObject $package -Name $field
                if ($null -ne $value) { $entry[$field] = $value }
            }
            [pscustomobject]$entry
        }
    )
    $provisioned = @(
        foreach ($package in $ProvisionedPackages) {
            $entry = [ordered]@{}
            foreach ($field in $provisionedFields) {
                $value = Get-ProjectObjectPropertyValue -InputObject $package -Name $field
                if ($null -ne $value) { $entry[$field] = $value }
            }
            [pscustomobject]$entry
        }
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    $document = [ordered]@{
        Format = "Microslop.AppxInventory"
        Version = 1
        CreatedUtc = [DateTime]::UtcNow.ToString("o")
        ComputerName = $env:COMPUTERNAME
        InstalledPackages = $installed
        ProvisionedPackages = $provisioned
        RecoveryNote = "Inventory only. This file does not contain package binaries or guarantee automatic reinstallation."
    }
    $temporary = $fullPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $document -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
    return $fullPath
}

function Invoke-ProjectAppxPackageRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Package,
        [Parameter(Mandatory = $true)][ValidateSet("Installed", "Provisioned")][string]$PackageType,
        [Parameter(Mandatory = $true)][string]$JournalPath
    )

    if ($PackageType -eq "Installed") {
        $identity = [string](Get-ProjectObjectPropertyValue -InputObject $Package -Name "PackageFullName")
        if ([string]::IsNullOrWhiteSpace($identity)) { throw "Installed Appx package has no PackageFullName." }
    } else {
        $identity = [string](Get-ProjectObjectPropertyValue -InputObject $Package -Name "PackageName")
        if ([string]::IsNullOrWhiteSpace($identity)) { throw "Provisioned Appx package has no PackageName." }
    }

    $operation = "Remove Appx $PackageType package"
    Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $operation -Category Irreversible -Status Started -Target $identity -Details "Package identity recorded in the Appx inventory; package payload is not backed up." | Out-Null
    try {
        if ($PackageType -eq "Installed") {
            Remove-AppxPackage -Package $identity -AllUsers -ErrorAction Stop
        } else {
            Remove-AppxProvisionedPackage -Online -PackageName $identity -ErrorAction Stop | Out-Null
        }
        Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $operation -Category Irreversible -Status Completed -Target $identity -Details "Removal command completed; reinstallation is not guaranteed by the inventory." | Out-Null
        return $true
    } catch {
        Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $operation -Category Irreversible -Status Failed -Target $identity -Details $_.Exception.Message | Out-Null
        if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
            Write-ProjectLog -Level WARNING -Message ("Appx removal failed for {0}: {1}" -f $identity, $_.Exception.Message)
        }
        return $false
    }
}

function Import-ProjectAppxInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Appx inventory not found: $Path" }
    $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($document.Format -ne "Microslop.AppxInventory" -or $document.Version -ne 1 -or $null -eq $document.InstalledPackages -or $null -eq $document.ProvisionedPackages) {
        throw "Unsupported or invalid Appx inventory."
    }
    foreach ($package in $document.InstalledPackages) {
        if ([string]::IsNullOrWhiteSpace([string]$package.PackageFullName)) { throw "Appx inventory contains an installed package without PackageFullName." }
    }
    foreach ($package in $document.ProvisionedPackages) {
        if ([string]::IsNullOrWhiteSpace([string]$package.PackageName)) { throw "Appx inventory contains a provisioned package without PackageName." }
    }
    return $document
}

function Get-ProjectAppxRecoveryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Inventory,
        [Parameter(Mandatory = $true)][object[]]$CurrentInstalledPackages,
        [Parameter(Mandatory = $true)][object[]]$CurrentProvisionedPackages
    )

    $installedNames = @($CurrentInstalledPackages | ForEach-Object { [string](Get-ProjectObjectPropertyValue -InputObject $_ -Name "PackageFullName") })
    $provisionedNames = @($CurrentProvisionedPackages | ForEach-Object { [string](Get-ProjectObjectPropertyValue -InputObject $_ -Name "PackageName") })
    $plan = @(
        foreach ($package in $Inventory.InstalledPackages) {
            $present = $installedNames -contains [string]$package.PackageFullName
            $locationExists = (-not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) -and (Test-Path -LiteralPath ([string]$package.InstallLocation) -PathType Container)
            [pscustomobject]@{
                PackageType = "Installed"
                Name = [string]$package.Name
                Identity = [string]$package.PackageFullName
                WasPresent = $true
                PresentNow = $present
                OriginalInstallLocationExists = [bool]$locationExists
                RecoveryHint = if ($present) { "No action needed." } elseif ($locationExists) { "Inspect the original AppxManifest.xml; registration may be possible, but is not guaranteed." } else { "Use Microsoft Store Library, the original vendor installer, or matching Windows installation media. Package binaries were not backed up." }
            }
        }
        foreach ($package in $Inventory.ProvisionedPackages) {
            $present = $provisionedNames -contains [string]$package.PackageName
            [pscustomobject]@{
                PackageType = "Provisioned"
                Name = [string]$package.DisplayName
                Identity = [string]$package.PackageName
                WasPresent = $true
                PresentNow = $present
                OriginalInstallLocationExists = $false
                RecoveryHint = if ($present) { "No action needed." } else { "Use matching Windows installation media or a trusted package source to reprovision. Provisioned package payload was not backed up." }
            }
        }
    )
    return $plan
}
