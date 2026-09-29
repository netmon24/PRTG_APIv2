function Suspend-PRTGDevice {
    <#
        .SYNOPSIS
        Pausiert ein Gerät (und damit alle seine Sensoren) in PRTG.

        .DESCRIPTION
        Suspend-PRTGDevice führt einen POST-Aufruf gegen /devices/{id}/pause aus.
        Optional kann eine Pausierungsnachricht und/oder ein Zeitpunkt angegeben
        werden, zu dem die Pause automatisch endet (sofern von der API-Version
        unterstützt; ansonsten bleibt das Gerät pausiert, bis es manuell mit
        Resume-PRTGDevice fortgesetzt wird).

        Hinweis zur Cmdlet-Benennung: PowerShell reserviert das Verb 'Pause' nicht
        in der Standard-Verbliste, weshalb gemäß PowerShell-Konventionen das
        genehmigte Verb 'Suspend' verwendet wird (siehe Get-Verb). In PRTG selbst
        sowie in der API heißt die Aktion weiterhin "pause". Ein Alias
        'Pause-PRTGDevice' wird zusätzlich bereitgestellt.

        .PARAMETER Id
        Objekt-ID des zu pausierenden Geräts. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Message
        Optionale Nachricht, die in PRTG als Pausierungsgrund angezeigt wird,
        z.B. 'Wartungsfenster Zertifikatswechsel'.

        .PARAMETER Filter
        Statt einer einzelnen -Id kann mit -Filter ein PRTG-API-Filterausdruck
        angegeben werden, um mehrere Geräte gleichzeitig zu pausieren
        (POST /devices/pause). -Id und -Filter schließen sich gegenseitig aus.

        .EXAMPLE
        Suspend-PRTGDevice -Id 2322 -Message 'Geplante Wartung'

        Pausiert das Gerät 2322 mit einer Begründung.

        .EXAMPLE
        Suspend-PRTGDevice -Filter 'group=Testumgebung'

        Pausiert alle Geräte, deren übergeordnete Gruppe "Testumgebung" heißt.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten (eines je betroffenem Gerät).
        Bei -Id: keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
    [Alias('Pause-PRTGDevice')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DeviceId')]
        [string[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByFilter')]
        [string]$Filter,

        [Parameter()]
        [string]$Message
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($deviceId in $Id) {
                    if ($PSCmdlet.ShouldProcess("Gerät $deviceId", "Pausieren")) {
                        $body = @{ message = $Message }
                        Invoke-PRTGRestMethod -Path "/devices/$deviceId/pause" -Method POST -Body $body | Out-Null
                    }
                }
            }
            'ByFilter' {
                if ($PSCmdlet.ShouldProcess("Geräte (Filter: $Filter)", "Pausieren")) {
                    $body = @{ filter = $Filter; message = $Message }
                    Invoke-PRTGRestMethod -Path '/devices/pause' -Method POST -Body $body
                }
            }
        }
    }
}
