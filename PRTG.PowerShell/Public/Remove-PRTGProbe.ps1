function Remove-PRTGProbe {
    <#
        .SYNOPSIS
        Löscht eine Probe inklusive aller untergeordneten Gruppen und Geräte.

        .DESCRIPTION
        Remove-PRTGProbe führt einen DELETE-Aufruf gegen
        /experimental/probes/{id} aus. Dieser Vorgang ist NICHT umkehrbar.
        Da eine Probe häufig sehr viele untergeordnete Objekte enthält, sollte
        dieses Cmdlet mit besonderer Vorsicht verwendet werden.

        .PARAMETER Id
        Objekt-ID der zu löschenden Probe. Auch über die Pipeline entgegennehmbar.

        .EXAMPLE
        Remove-PRTGProbe -Id 5

        Löscht die Probe mit der ID 5 nach Bestätigung durch den Anwender.

        .OUTPUTS
        Keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ProbeId')]
        [string[]]$Id
    )

    process {
        foreach ($probeId in $Id) {
            if ($PSCmdlet.ShouldProcess("Probe $probeId", "Endgültig löschen (inkl. aller Gruppen/Geräte/Sensoren)")) {
                Invoke-PRTGRestMethod -Path "/experimental/probes/$probeId" -Method DELETE | Out-Null
            }
        }
    }
}
