function Get-PRTGDevice {
    <#
        .SYNOPSIS
        Liest ein oder mehrere Geräte (Devices) aus PRTG.

        .DESCRIPTION
        Get-PRTGDevice ruft entweder ein einzelnes Gerät über dessen Objekt-ID ab
        (GET /devices/{id}) oder eine gefilterte Liste aller Geräte
        (GET /experimental/devices). Für Listenabrufe wird automatisch Paging
        durchgeführt, sodass auch Umgebungen mit mehreren tausend Geräten
        vollständig erfasst werden.

        .PARAMETER Id
        Objekt-ID des gewünschten Geräts. Kann auch über die Pipeline (z.B. von
        Get-PRTGObject) übergeben werden.

        .PARAMETER Filter
        PRTG-API-Filterausdruck zur Einschränkung der Ergebnisliste, z.B.
        'active=true' oder 'status=Down'. Siehe PRTG API v2 Overview: Filters.
        Wird ignoriert, wenn -Id angegeben ist.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte, die in die Antwort aufgenommen werden sollen,
        z.B. 'sensor_status_summary', 'all_sections' oder konkrete Settings-Bereiche
        wie 'intervalgroup'. Mehrere Werte sind als Array möglich.

        .PARAMETER First
        Begrenzt die Anzahl der zurückgegebenen Geräte bei einer Listenabfrage.

        .EXAMPLE
        Get-PRTGDevice -Id 2322

        Liest das Gerät mit der ID 2322.

        .EXAMPLE
        Get-PRTGDevice -Filter 'active=true' -Include sensor_status_summary

        Listet alle aktiven Geräte inklusive Sensor-Status-Zusammenfassung.

        .EXAMPLE
        Get-PRTGGroup -Filter 'name=@sub(Hannover)' | Get-PRTGDevice

        Liefert alle Geräte innerhalb von Gruppen, deren Name "Hannover" enthält
        (Beispiel für die Kombination mehrerer Cmdlets über die Pipeline; setzt
        voraus, dass Get-PRTGGroup-Ergebnisse eine Id-Eigenschaft besitzen).

        .OUTPUTS
        PSCustomObject mit den Geräte-Eigenschaften (id, name, host, status, ...).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('DeviceId')]
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
                foreach ($deviceId in $Id) {
                    $query = @{}
                    if ($Include) { $query['include'] = $Include }
                    Invoke-PRTGRestMethod -Path "/devices/$deviceId" -Method GET -QueryParameter $query
                }
            }
            'List' {
                $query = @{}
                if ($Filter)  { $query['filter']  = $Filter }
                if ($Include) { $query['include'] = $Include }
                Get-PRTGPagedResult -Path '/experimental/devices' -QueryParameter $query -First $First
            }
        }
    }
}
