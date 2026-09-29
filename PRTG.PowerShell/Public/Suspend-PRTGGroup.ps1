function Suspend-PRTGGroup {
    <#
        .SYNOPSIS
        Pausiert eine Gruppe (und damit alle untergeordneten Geräte/Sensoren) in PRTG.

        .DESCRIPTION
        Suspend-PRTGGroup führt einen POST-Aufruf gegen /groups/{id}/pause aus.
        Ein Alias 'Pause-PRTGGroup' wird für Anwender bereitgestellt, die sich an
        der PRTG-Terminologie ("Pause") orientieren möchten; PowerShell-konform
        ist jedoch 'Suspend'.

        .PARAMETER Id
        Objekt-ID der zu pausierenden Gruppe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Message
        Optionale Nachricht, die als Pausierungsgrund angezeigt wird.

        .PARAMETER Filter
        PRTG-API-Filterausdruck, um mehrere Gruppen gleichzeitig zu pausieren
        (POST /groups/pause). Schließt sich mit -Id gegenseitig aus.

        .EXAMPLE
        Suspend-PRTGGroup -Id 1044 -Message 'Wartungsfenster'

        Pausiert die Gruppe 1044 mit Begründung.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten. Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
    [Alias('Pause-PRTGGroup')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter,

        [Parameter()]
        [string]$Message
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($groupId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Gruppe $groupId", "Pausieren")) {
                        $body = @{ message = $Message }
                        Invoke-PRTGRestMethod -Path "/groups/$groupId/pause" -Method POST -Body $body | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Gruppen (Filter: $Filter)", "Pausieren")) {
                    $body = @{ filter = $Filter; message = $Message }
                    Invoke-PRTGRestMethod -Path '/groups/pause' -Method POST -Body $body
                }
            }
        }
    }
}
