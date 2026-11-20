# Shared logging helpers for Setting-up-Microslop.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Initialize-ProjectLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$LogDirectory = (Join-Path (Get-Location).Path "Logs")
    )

    $logDirectory = $LogDirectory
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

function Invoke-ProjectNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),
        [int[]]$AllowedExitCodes = @(0),
        [switch]$ContinueOnError
    )

    Write-ProjectLog -Level INFO -Message ("Starting external command: {0} {1}" -f $FilePath, ($ArgumentList -join " "))
    try {
        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                Write-ProjectLog -Level INFO -Message ([string]$line)
            }
        }
    } catch {
        Write-ProjectLog -Level ERROR -Message ("Could not execute '{0}': {1}" -f $FilePath, $_.Exception.Message)
        if (-not $ContinueOnError) { throw }
        return 1
    }

    if ($AllowedExitCodes -notcontains $exitCode) {
        $message = "External command failed with exit code ${exitCode}: $FilePath"
        if ($ContinueOnError) {
            Write-ProjectLog -Level WARNING -Message $message
        } else {
            Write-ProjectLog -Level ERROR -Message $message
            throw $message
        }
    } else {
        Write-ProjectLog -Level INFO -Message ("External command completed with exit code {0}: {1}" -f $exitCode, $FilePath)
    }

    return $exitCode
}
