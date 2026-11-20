# Shared logging helpers for Setting-up-Microslop.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Initialize-ProjectLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $logDirectory = Join-Path $PSScriptRoot "Logs"
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $safeName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptName)
    $script:ProjectLogPath = Join-Path $logDirectory ("{0}-{1}.log" -f $safeName, (Get-Date -Format "yyyyMMdd-HHmmss"))
    Write-ProjectLog -Level INFO -Message "Execution started."
    return $script:ProjectLogPath
}

function Write-ProjectLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    if (-not [string]::IsNullOrWhiteSpace($script:ProjectLogPath)) {
        try {
            Add-Content -LiteralPath $script:ProjectLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Warning "Unable to write project log: $($_.Exception.Message)"
        }
    }

    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        default   { Write-Host $line -ForegroundColor Gray }
    }
}

function Complete-ProjectLogging {
    [CmdletBinding()]
    param(
        [string]$Message = "Execution finished."
    )
    Write-ProjectLog -Level INFO -Message $Message
}
