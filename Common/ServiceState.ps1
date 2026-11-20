# Helpers for restoring service state after temporary maintenance.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

function Restore-ProjectServiceStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$WasRunning,

        [string[]]$ServiceNames = @()
    )

    foreach ($name in $ServiceNames) {
        if ($WasRunning.ContainsKey($name) -and $WasRunning[$name]) {
            try {
                Start-Service -Name $name -ErrorAction Stop
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                    Write-ProjectLog -Level INFO -Message "Restored service to Running: $name"
                }
            } catch {
                $message = "Could not restore service '$name': $($_.Exception.Message)"
                if (Get-Command Write-ProjectLog -ErrorAction SilentlyContinue) {
                    Write-ProjectLog -Level WARNING -Message $message
                } else {
                    Write-Warning $message
                }
            }
        }
    }
}
