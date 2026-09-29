function Get-PRTGChannel {
    <#
        .SYNOPSIS
        Liest einen oder mehrere Kanäle (Channels) eines Sensors aus PRTG.

        .DESCRIPTION
        Get-PRTGChannel ruft entweder einen einzelnen Kanal über dessen Objekt-ID
        ab (GET /channels/{id}) oder eine Liste aller Kanäle
        (GET /experimental/channels). Kanal-IDs haben in PRTG das Format
        '<SensorId>.<ChannelIndex>', z.B. '3074.1'.

        .PARAMETER Id
        Objekt-ID des gewünschten Kanals, z.B. '3074.1'.

        .PARAMETER Include
        Zusätzliche Detail-Abschnitte, z.B. 'alerting', 'values', 'all_sections'.

        .PARAMETER First
        Begrenzt die Anzahl der zurückgegebenen Kanäle bei einer Listenabfrage.

        .EXAMPLE
        Get-PRTGChannel -Id '3074.1'

        Liest Kanal 1 des Sensors mit der ID 3074.

        .EXAMPLE
        Get-PRTGChannel -Include values

        Listet alle Kanäle inklusive ihrer aktuellen Messwerte.

        .OUTPUTS
        PSCustomObject mit den Kanal-Eigenschaften (id, name, lastvalue, ...).
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('ChannelId')]
        [string[]]$Id,

        [Parameter()]
        [string[]]$Include,

        [Parameter(ParameterSetName = 'List')]
        [int]$First = 0
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                foreach ($channelId in $Id) {
                    $query = @{}
                    if ($Include) { $query['include'] = $Include }
                    Invoke-PRTGRestMethod -Path "/channels/$channelId" -Method GET -QueryParameter $query
                }
            }
            'List' {
                $query = @{}
                if ($Include) { $query['include'] = $Include }
                Get-PRTGPagedResult -Path '/experimental/channels' -QueryParameter $query -First $First
            }
        }
    }
}
