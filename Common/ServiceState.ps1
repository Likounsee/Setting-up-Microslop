# Helpers for restoring service state after temporary maintenance.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Restore-ProjectServiceStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$WasRunning,

        [string[]]$ServiceNames = @()
    )

    $success = $true
    foreach ($name in $ServiceNames) {
        if ($WasRunning.ContainsKey($name) -and $WasRunning[$name]) {
            try {
                $currentService = Get-Service -Name $name -ErrorAction Stop
                if ($currentService.Status -ne 'Running') {
                    Start-Service -Name $name -ErrorAction Stop
                }
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                    Write-ProjectLog -Level INFO -Message "Restored service to Running: $name"
                }
            } catch {
                $success = $false
                $message = "Could not restore service '$name': $($_.Exception.Message)"
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                    Write-ProjectLog -Level WARNING -Message $message
                } else {
                    Write-Warning $message
                }
            }
        }
    }
    return $success
}


function Save-ProjectServiceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$WasRunning,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { throw "Service backup path must include a directory." }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    }

    $services = @()
    foreach ($name in $WasRunning.Keys) {
        if ([string]$name -notmatch '^[A-Za-z0-9_.-]{1,256}$') { throw "Invalid service name in snapshot." }
        $services += [ordered]@{ Name = [string]$name; WasRunning = [bool]$WasRunning[$name] }
    }
    $document = [ordered]@{
        Format = 'Microslop.ServiceBackup'
        Version = 1
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Services = $services
    }
    $temporaryPath = $Path + '.tmp'
    try {
        [System.IO.File]::WriteAllText($temporaryPath, (ConvertTo-Json -InputObject $document -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        throw
    }
    if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
        Write-ProjectLog -Level INFO -Message ("Persistent service-state backup saved ({0} services): {1}" -f $services.Count, $Path)
    }
    return $Path
}

function Import-ProjectServiceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Service backup file not found: $Path" }
    $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($document.Format -ne 'Microslop.ServiceBackup' -or $document.Version -ne 1 -or $null -eq $document.Services) {
        throw "Unsupported or invalid service backup format."
    }
    $snapshot = @{}
    foreach ($service in @($document.Services)) {
        $name = [string]$service.Name
        if ($name -notmatch '^[A-Za-z0-9_.-]{1,256}$' -or $snapshot.ContainsKey($name)) {
            throw "Service backup contains an invalid or duplicate service name."
        }
        $snapshot[$name] = [bool]$service.WasRunning
    }
    return ,$snapshot
}

function Restore-ProjectServiceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Snapshot)

    $names = @($Snapshot.Keys)
    return (Restore-ProjectServiceStates -WasRunning $Snapshot -ServiceNames $names)
}
