# Persistent operation journal for maintenance actions that cannot be rolled back.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Write-ProjectOperationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][ValidateSet("Reversible", "Regenerable", "Irreversible", "Informational")][string]$Category,
        [Parameter(Mandatory = $true)][ValidateSet("Started", "Completed", "Failed", "Skipped")][string]$Status,
        [string]$Target = "",
        [string]$Details = "",
        [Nullable[int]]$ExitCode
    )

    if ([string]::IsNullOrWhiteSpace($Operation) -or $Operation.Length -gt 256) {
        throw "Operation name must contain 1 to 256 characters."
    }
    if ($Target.Length -gt 2048 -or $Details.Length -gt 4096) {
        throw "Operation journal fields exceed their maximum length."
    }

    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($JournalPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }

    $document = $null
    if (Test-Path -LiteralPath $JournalPath -PathType Leaf) {
        $document = Get-Content -LiteralPath $JournalPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($document.Format -ne "Microslop.OperationJournal" -or $document.Version -ne 1 -or $null -eq $document.Records) {
            throw "Unsupported or invalid operation journal."
        }
    } else {
        $document = [ordered]@{
            Format = "Microslop.OperationJournal"
            Version = 1
            CreatedUtc = [DateTime]::UtcNow.ToString("o")
            Records = @()
        }
    }

    $record = [ordered]@{
        TimestampUtc = [DateTime]::UtcNow.ToString("o")
        Operation = $Operation
        Category = $Category
        Status = $Status
        Target = $Target
        Details = $Details
        ExitCode = $ExitCode
    }
    $records = @($document.Records) + @($record)
    $updated = [ordered]@{
        Format = "Microslop.OperationJournal"
        Version = 1
        CreatedUtc = [string]$document.CreatedUtc
        Records = $records
    }
    $temporary = $JournalPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $updated -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $JournalPath -PathType Leaf) {
            Move-Item -LiteralPath $temporary -Destination $JournalPath -Force -ErrorAction Stop
        } else {
            Move-Item -LiteralPath $temporary -Destination $JournalPath -ErrorAction Stop
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
    return $JournalPath
}

function Invoke-ProjectTrackedNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][ValidateSet("Regenerable", "Irreversible")][string]$Category,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [string]$Target = "",
        [int[]]$AllowedExitCodes = @(0),
        [switch]$ContinueOnError
    )

    $commandText = (@($FilePath) + @($ArgumentList)) -join " "
    Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $Operation -Category $Category -Status Started -Target $Target -Details $commandText | Out-Null
    try {
        $exitCode = Invoke-ProjectNativeCommand -FilePath $FilePath -ArgumentList $ArgumentList -AllowedExitCodes $AllowedExitCodes -ContinueOnError:$ContinueOnError
        $status = if ($AllowedExitCodes -contains $exitCode) { "Completed" } else { "Failed" }
        Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $Operation -Category $Category -Status $status -Target $Target -Details $commandText -ExitCode $exitCode | Out-Null
        return $exitCode
    } catch {
        Write-ProjectOperationRecord -JournalPath $JournalPath -Operation $Operation -Category $Category -Status Failed -Target $Target -Details ($commandText + " | " + $_.Exception.Message) | Out-Null
        if (-not $ContinueOnError) { throw }
        return 1
    }
}
