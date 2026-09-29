function Resume-PRTGDevice {
    <#
        .SYNOPSIS
        Setzt ein pausiertes Gerät in PRTG fort.

        .DESCRIPTION
        Resume-PRTGDevice führt einen POST-Aufruf gegen /devices/{id}/resume aus
        und beendet damit eine zuvor mit Suspend-PRTGDevice (oder über die
        Weboberfläche) gesetzte Pause. 'Resume' ist bereits ein von PowerShell
        genehmigtes Verb, daher gibt es hier keinen Namenskonflikt.

        .PARAMETER Id
        Objekt-ID des fortzusetzenden Geräts. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Filter
        Statt einer einzelnen -Id kann mit -Filter ein PRTG-API-Filterausdruck
        angegeben werden, um mehrere Geräte gleichzeitig fortzusetzen
        (POST /devices/resume). -Id und -Filter schließen sich gegenseitig aus.

        .EXAMPLE
        Resume-PRTGDevice -Id 2322

        Setzt das Gerät 2322 fort.

        .EXAMPLE
        Resume-PRTGDevice -Filter 'group=Testumgebung'

        Setzt alle Geräte fort, deren übergeordnete Gruppe "Testumgebung" heißt.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten (eines je betroffenem Gerät).
        Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DeviceId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($deviceId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Gerät $deviceId", "Fortsetzen")) {
                        Invoke-PRTGRestMethod -Path "/devices/$deviceId/resume" -Method POST | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Geräte (Filter: $Filter)", "Fortsetzen")) {
                    $body = @{ filter = $Filter }
                    Invoke-PRTGRestMethod -Path '/devices/resume' -Method POST -Body $body
                }
            }
        }
    }
}
