function Get-PRTGProbe {
    <#
        .SYNOPSIS
        Liest eine oder mehrere Probes (Sondenrechner) aus PRTG.

        .DESCRIPTION
        Get-PRTGProbe ruft entweder eine einzelne Probe über deren Objekt-ID ab
        (GET /probes/{id}) oder eine gefilterte Liste aller Probes
        (GET /experimental/probes). Listenabrufe werden automatisch vollständig
        durchpaginiert.

        .PARAMETER Id
        Objekt-ID der gewünschten Probe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Filter
        PRTG-API-Filterausdruck zur Einschränkung der Ergebnisliste.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte wie 'sensor_status_summary' oder 'all_sections'.

        .PARAMETER First
        Begrenzt die Anzahl der zurückgegebenen Probes bei einer Listenabfrage.

        .EXAMPLE
        Get-PRTGProbe -Id 1

        Liest die Probe mit der ID 1 (in der Regel die lokale Probe).

        .EXAMPLE
        Get-PRTGProbe -Include sensor_status_summary

        Listet alle Probes inklusive Sensor-Status-Zusammenfassung.

        .OUTPUTS
        PSCustomObject mit den Probe-Eigenschaften.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('ProbeId')]
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
                foreach ($probeId in $Id) {
                    $query = @{}
                    if ($Include) { $query['include'] = $Include }
                    Invoke-PRTGRestMethod -Path "/probes/$probeId" -Method GET -QueryParameter $query
                }
            }
            'List' {
                $query = @{}
                if ($Filter)  { $query['filter']  = $Filter }
                if ($Include) { $query['include'] = $Include }
                Get-PRTGPagedResult -Path '/experimental/probes' -QueryParameter $query -First $First
            }
        }
    }
}
