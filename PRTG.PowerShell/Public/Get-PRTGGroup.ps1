function Get-PRTGGroup {
    <#
        .SYNOPSIS
        Liest eine oder mehrere Gruppen aus PRTG.

        .DESCRIPTION
        Get-PRTGGroup ruft entweder eine einzelne Gruppe über deren Objekt-ID ab
        (GET /groups/{id}) oder eine gefilterte Liste aller Gruppen
        (GET /experimental/groups). Listenabrufe werden automatisch vollständig
        durchpaginiert.

        .PARAMETER Id
        Objekt-ID der gewünschten Gruppe. Auch über die Pipeline entgegennehmbar.

        .PARAMETER Filter
        PRTG-API-Filterausdruck, z.B. 'name=@sub(Server)'. Wird ignoriert, wenn
        -Id angegeben ist.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte wie 'sensor_status_summary' oder 'all_sections'.

        .PARAMETER First
        Begrenzt die Anzahl der zurückgegebenen Gruppen bei einer Listenabfrage.

        .EXAMPLE
        Get-PRTGGroup -Id 1044

        Liest die Gruppe mit der ID 1044.

        .EXAMPLE
        Get-PRTGGroup -Filter 'status=Down' -Include sensor_status_summary

        Listet alle Gruppen mit Status "Down" inklusive Sensor-Status-Übersicht.

        .OUTPUTS
        PSCustomObject mit den Gruppen-Eigenschaften.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
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
                foreach ($groupId in $Id) {
                    $query = @{}
                    if ($Include) { $query['include'] = $Include }
                    Invoke-PRTGRestMethod -Path "/groups/$groupId" -Method GET -QueryParameter $query
                }
            }
            'List' {
                $query = @{}
                if ($Filter)  { $query['filter']  = $Filter }
                if ($Include) { $query['include'] = $Include }
                Get-PRTGPagedResult -Path '/experimental/groups' -QueryParameter $query -First $First
            }
        }
    }
}
