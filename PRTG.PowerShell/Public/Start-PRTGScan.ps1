function Start-PRTGScan {
    <#
        .SYNOPSIS
        Löst eine sofortige Prüfung ("Scan Now") für Geräte, Gruppen oder Probes aus.

        .DESCRIPTION
        Start-PRTGScan bündelt die drei "Scan Now"-Endpunkte der PRTG API v2
        (/devices/{id}/scan, /groups/{id}/scan, /probes/{id}/scan sowie deren
        Filter-basierte Multi-Varianten) in einem einzigen, einheitlichen Cmdlet.
        Es entspricht der Funktion "Jetzt prüfen" in der PRTG-Weboberfläche und
        löst eine sofortige Sensorabfrage aus, statt auf das nächste reguläre
        Scan-Intervall zu warten.

        .PARAMETER DeviceId
        Objekt-ID eines Geräts, dessen Sensoren sofort geprüft werden sollen.

        .PARAMETER GroupId
        Objekt-ID einer Gruppe, deren Sensoren sofort geprüft werden sollen.

        .PARAMETER ProbeId
        Objekt-ID einer Probe, deren Sensoren sofort geprüft werden sollen.

        .PARAMETER Filter
        PRTG-API-Filterausdruck zur Auswahl mehrerer Objekte. Muss zusammen mit
        -ObjectType angegeben werden.

        .PARAMETER ObjectType
        Objekttyp für die filterbasierte Mehrfachauswahl: 'Device', 'Group' oder
        'Probe'. Nur in Kombination mit -Filter relevant.

        .EXAMPLE
        Start-PRTGScan -DeviceId 2322

        Löst eine sofortige Prüfung aller Sensoren des Geräts 2322 aus.

        .EXAMPLE
        Start-PRTGScan -Filter 'group=Webserver' -ObjectType Device

        Löst eine sofortige Prüfung aller Geräte aus, deren übergeordnete Gruppe
        "Webserver" heißt.

        .OUTPUTS
        Bei -Filter: Array von ActionResult-Objekten. Bei -DeviceId/-GroupId/-ProbeId:
        keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'Device')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Device', ValueFromPipelineByPropertyName)]
        [string[]]$DeviceId,

        [Parameter(Mandatory, ParameterSetName = 'Group', ValueFromPipelineByPropertyName)]
        [string[]]$GroupId,

        [Parameter(Mandatory, ParameterSetName = 'Probe', ValueFromPipelineByPropertyName)]
        [string[]]$ProbeId,

        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$Filter,

        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [ValidateSet('Device', 'Group', 'Probe')]
        [string]$ObjectType
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Device' {
                foreach ($id in $DeviceId) {
                    if ($PSCmdlet.ShouldProcess("Gerät $id", "Sofortige Prüfung auslösen")) {
                        Invoke-PRTGRestMethod -Path "/devices/$id/scan" -Method POST | Out-Null
                    }
                }
            }
            'Group' {
                foreach ($id in $GroupId) {
                    if ($PSCmdlet.ShouldProcess("Gruppe $id", "Sofortige Prüfung auslösen")) {
                        Invoke-PRTGRestMethod -Path "/groups/$id/scan" -Method POST | Out-Null
                    }
                }
            }
            'Probe' {
                foreach ($id in $ProbeId) {
                    if ($PSCmdlet.ShouldProcess("Probe $id", "Sofortige Prüfung auslösen")) {
                        Invoke-PRTGRestMethod -Path "/probes/$id/scan" -Method POST | Out-Null
                    }
                }
            }
            'Filter' {
                $path = switch ($ObjectType) {
                    'Device' { '/devices/scan' }
                    'Group'  { '/groups/scan' }
                    'Probe'  { '/probes/scan' }
                }
                if ($PSCmdlet.ShouldProcess("$ObjectType (Filter: $Filter)", "Sofortige Prüfung auslösen")) {
                    $body = @{ filter = $Filter }
                    Invoke-PRTGRestMethod -Path $path -Method POST -Body $body
                }
            }
        }
    }
}
