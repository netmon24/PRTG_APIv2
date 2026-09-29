function Get-PRTGObject {
    <#
        .SYNOPSIS
        Liest beliebige Monitoring-Objekte (Probes, Gruppen, Geräte, Sensoren, Kanäle)
        über den generischen Objekt-Endpunkt von PRTG.

        .DESCRIPTION
        Get-PRTGObject ist das allgemeinste Lese-Cmdlet des Moduls. Es nutzt
        GET /experimental/objects und kann durch einen Filterausdruck auf
        beliebige Objekttypen, Status oder Namen eingeschränkt werden.
        Für die meisten alltäglichen Aufgaben sind die spezialisierten Cmdlets
        (Get-PRTGDevice, Get-PRTGGroup, Get-PRTGProbe, Get-PRTGSensor) komfortabler;
        Get-PRTGObject ist hilfreich für übergreifende Abfragen, z.B. "alle
        Objekte gleich welchen Typs mit Status 'Down'".

        .PARAMETER Filter
        PRTG-API-Filterausdruck, z.B. 'status=Down' oder 'type=device;active=true'.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte, z.B. 'sensor_status_summary', 'all_sections', 'path'.

        .PARAMETER First
        Begrenzt die Gesamtanzahl der zurückgegebenen Objekte.

        .EXAMPLE
        Get-PRTGObject -Filter 'status=Down'

        Liefert alle Objekte (unabhängig vom Typ) mit Status "Down".

        .EXAMPLE
        Get-PRTGObject -Filter 'type=device' -Include path

        Liefert alle Geräte inklusive ihres vollständigen Pfads im Objektbaum.

        .OUTPUTS
        PSCustomObject (TreeNode) mit u.a. id, name, type, status, href.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string[]]$Include,

        [Parameter()]
        [int]$First = 0
    )

    $query = @{}
    if ($Filter)  { $query['filter']  = $Filter }
    if ($Include) { $query['include'] = $Include }

    Get-PRTGPagedResult -Path '/experimental/objects' -QueryParameter $query -First $First
}
