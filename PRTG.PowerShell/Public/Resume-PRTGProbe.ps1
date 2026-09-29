function Resume-PRTGProbe {
    <#
        .SYNOPSIS
        Setzt eine pausierte Probe in PRTG fort.

        .DESCRIPTION
        Resume-PRTGProbe führt einen POST-Aufruf gegen /probes/{id}/resume aus.

        .PARAMETER Id
        Objekt-ID der fortzusetzenden Probe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Filter
        PRTG-API-Filterausdruck, um mehrere Probes gleichzeitig fortzusetzen
        (POST /probes/resume). Schließt sich mit -Id gegenseitig aus.

        .EXAMPLE
        Resume-PRTGProbe -Id 5

        Setzt die Probe 5 fort.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten. Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ProbeId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($probeId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Probe $probeId", "Fortsetzen")) {
                        Invoke-PRTGRestMethod -Path "/probes/$probeId/resume" -Method POST | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Probes (Filter: $Filter)", "Fortsetzen")) {
                    $body = @{ filter = $Filter }
                    Invoke-PRTGRestMethod -Path '/probes/resume' -Method POST -Body $body
                }
            }
        }
    }
}
