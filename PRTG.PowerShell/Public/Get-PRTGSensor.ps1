function Get-PRTGSensor {
    <#
        .SYNOPSIS
        Liest einen oder mehrere Sensoren aus PRTG.

        .DESCRIPTION
        PRTG API v2 bietet (Stand des aktuellen API-Reifegrads) keinen dedizierten
        '/sensors'-Listen-Endpunkt analog zu Devices/Groups/Probes. Sensoren werden
        daher über den generischen Objekt-Endpunkt (GET /experimental/objects) mit
        einem Typfilter abgefragt, bzw. einzeln über GET /devices/{id} mit
        include=all_sections, sofern eine direkte Objekt-ID bekannt ist und über
        den allgemeinen Baum referenziert wird.

        In der Praxis ist der zuverlässigste Weg, einen einzelnen Sensor anhand
        seiner ID zu lesen, der allgemeine TreeNode-Endpunkt unter /experimental/objects
        mit einem Filter auf die ID bzw. den Typ 'sensor'.

        .PARAMETER Id
        Objekt-ID des gewünschten Sensors.

        .PARAMETER Filter
        PRTG-API-Filterausdruck zur Einschränkung der Ergebnisliste, z.B.
        'type=sensor;status=Down'. Wird ignoriert, wenn -Id angegeben ist.
        Hinweis: Ohne einschränkenden Filter liefert /experimental/objects ALLE
        Objekttypen (Probes, Gruppen, Geräte, Sensoren, Kanäle) zurück; dieses
        Cmdlet ergänzt daher automatisch einen Typfilter auf Sensoren, sofern kein
        eigener 'type='-Bestandteil im übergebenen Filter enthalten ist.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte, z.B. 'all_sections', 'path'.

        .PARAMETER First
        Begrenzt die Anzahl der zurückgegebenen Sensoren bei einer Listenabfrage.

        .EXAMPLE
        Get-PRTGSensor -Id 3074

        Liest den Sensor mit der ID 3074.

        .EXAMPLE
        Get-PRTGSensor -Filter 'status=Down'

        Listet alle Sensoren mit Status "Down".

        .OUTPUTS
        PSCustomObject mit den Sensor-Eigenschaften (id, name, type, status, ...).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('SensorId')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'List')]
        [string]$Filter,

        [Parameter()]
        [string[]]$Include,

        [Parameter(ParameterSetName = 'List')]
        [int]$First = 0
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($sensorId in $Id) {
                    $query = @{ filter = "id=$sensorId" }
                    if ($Include) { $query['include'] = $Include }
                    $result = Get-PRTGPagedResult -Path '/experimental/objects' -QueryParameter $query -First 1
                    $result
                }
            }
            'List' {
                $effectiveFilter = $Filter
                if (-not $effectiveFilter) {
                    $effectiveFilter = 'type=sensor'
                }
                elseif ($effectiveFilter -notmatch 'type=') {
                    $effectiveFilter = "type=sensor;$effectiveFilter"
                }

                $query = @{ filter = $effectiveFilter }
                if ($Include) { $query['include'] = $Include }
                Get-PRTGPagedResult -Path '/experimental/objects' -QueryParameter $query -First $First
            }
        }
    }
}
