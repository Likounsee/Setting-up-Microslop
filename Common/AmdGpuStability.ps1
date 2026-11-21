# AMD GPU detection and ULPS registry discovery helpers.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Get-ProjectAmdDisplayDevices {
    [CmdletBinding()]
    param()

    return @(Get-PnpDevice -Class Display -Status OK -ErrorAction Stop |
        Where-Object { $_.InstanceId -like "PCI\VEN_1002*" })
}

function Get-ProjectAmdUlpsRegistryPaths {
    [CmdletBinding()]
    param(
        [string]$RegistryClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    )

    $paths = @()
    foreach ($key in @(Get-ChildItem -LiteralPath $RegistryClassPath -ErrorAction Stop)) {
        $properties = Get-ItemProperty -LiteralPath $key.PSPath -Name "EnableUlps" -ErrorAction SilentlyContinue
        if ($null -ne $properties -and $properties.PSObject.Properties.Name -contains "EnableUlps") {
            $paths += (Join-Path -Path $RegistryClassPath -ChildPath $key.PSChildName)
        }
    }
    return $paths
}
