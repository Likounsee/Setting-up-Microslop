# Shared helpers for collecting and formatting PowerShell module errors.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Get-ProjectErrorRecords {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Output = @()
    )

    return @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
}

function Format-ProjectErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )

    $lines = @(
        "Module: $ModuleName",
        "Exception type: $($ErrorRecord.Exception.GetType().FullName)",
        "Message: $($ErrorRecord.Exception.Message)"
    )

    if ($ErrorRecord.FullyQualifiedErrorId) {
        $lines += "FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)"
    }
    if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.PositionMessage) {
        $lines += $ErrorRecord.InvocationInfo.PositionMessage
    }
    if ($ErrorRecord.ScriptStackTrace) {
        $lines += ("Stack trace:" + [Environment]::NewLine + $ErrorRecord.ScriptStackTrace)
    }

    return ($lines -join [Environment]::NewLine)
}
