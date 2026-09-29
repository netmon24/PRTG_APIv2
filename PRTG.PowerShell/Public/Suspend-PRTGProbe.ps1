function Suspend-PRTGProbe {
    <#
        .SYNOPSIS
        Pausiert eine Probe (und damit alle untergeordneten Gruppen/Geräte/Sensoren) in PRTG.

        .DESCRIPTION
        Suspend-PRTGProbe führt einen POST-Aufruf gegen /probes/{id}/pause aus.
        Ein Alias 'Pause-PRTGProbe' wird zusätzlich bereitgestellt.

        .PARAMETER Id
        Objekt-ID der zu pausierenden Probe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Message
        Optionale Nachricht, die als Pausierungsgrund angezeigt wird.

        .PARAMETER Filter
        PRTG-API-Filterausdruck, um mehrere Probes gleichzeitig zu pausieren
        (POST /probes/pause). Schließt sich mit -Id gegenseitig aus.

        .EXAMPLE
        Suspend-PRTGProbe -Id 5 -Message 'Wartung Sondenrechner'

        Pausiert die Probe 5 mit Begründung.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten. Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
    [Alias('Pause-PRTGProbe')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ProbeId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter,

        [Parameter()]
        [string]$Message
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($probeId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Probe $probeId", "Pausieren")) {
                        $body = @{ message = $Message }
                        Invoke-PRTGRestMethod -Path "/probes/$probeId/pause" -Method POST -Body $body | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Probes (Filter: $Filter)", "Pausieren")) {
                    $body = @{ filter = $Filter; message = $Message }
                    Invoke-PRTGRestMethod -Path '/probes/pause' -Method POST -Body $body
                }
            }
        }
    }
}
