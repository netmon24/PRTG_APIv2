function Resume-PRTGGroup {
    <#
        .SYNOPSIS
        Setzt eine pausierte Gruppe in PRTG fort.

        .DESCRIPTION
        Resume-PRTGGroup führt einen POST-Aufruf gegen /groups/{id}/resume aus.

        .PARAMETER Id
        Objekt-ID der fortzusetzenden Gruppe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Filter
        PRTG-API-Filterausdruck, um mehrere Gruppen gleichzeitig fortzusetzen
        (POST /groups/resume). Schließt sich mit -Id gegenseitig aus.

        .EXAMPLE
        Resume-PRTGGroup -Id 1044

        Setzt die Gruppe 1044 fort.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten. Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($groupId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Gruppe $groupId", "Fortsetzen")) {
                        Invoke-PRTGRestMethod -Path "/groups/$groupId/resume" -Method POST | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Gruppen (Filter: $Filter)", "Fortsetzen")) {
                    $body = @{ filter = $Filter }
                    Invoke-PRTGRestMethod -Path '/groups/resume' -Method POST -Body $body
                }
            }
        }
    }
}
