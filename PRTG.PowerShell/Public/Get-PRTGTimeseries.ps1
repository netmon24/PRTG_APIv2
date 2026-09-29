function Get-PRTGTimeseries {
    <#
        .SYNOPSIS
        Liest historische Messwerte (Zeitreihen) eines Sensors aus PRTG.

        .DESCRIPTION
        Get-PRTGTimeseries ruft GET /experimental/timeseries/{id}/{type} auf und
        liefert tabellarische Zeitreihendaten für vordefinierte Zeitfenster:
        'Live' (letzte 4 Stunden), 'Short' (letzte 2 Tage), 'Medium' (letzte 60
        Tage) oder 'Long' (letztes Jahr).

        Die Rohantwort der API ist ein Array von Arrays (erste Zeile = Header,
        bestehend aus 'time' und den Kanal-IDs). Dieses Cmdlet wandelt das
        Ergebnis standardmäßig in handlichere PSCustomObjects mit benannten
        Eigenschaften um.

        .PARAMETER SensorId
        Objekt-ID des Sensors, dessen Zeitreihendaten gelesen werden sollen.

        .PARAMETER TimeRange
        Vordefiniertes Zeitfenster: 'Live', 'Short', 'Medium' oder 'Long'.
        Standard: 'Live'.

        .PARAMETER ChannelId
        Optionale Liste von Kanal-IDs (Format '<SensorId>.<Index>', z.B. '3074.1'),
        um die Antwort auf bestimmte Kanäle einzuschränken. Ohne Angabe werden
        alle Kanäle zurückgegeben.

        .PARAMETER Raw
        Gibt die rohe Tabellenstruktur (Array von Arrays) zurück, wie sie die
        API liefert, ohne Konvertierung in benannte Objekte.

        .EXAMPLE
        Get-PRTGTimeseries -SensorId 3074 -TimeRange Short

        Liest die Messwerte der letzten 2 Tage für Sensor 3074.

        .EXAMPLE
        Get-PRTGTimeseries -SensorId 3074 -ChannelId '3074.1' -TimeRange Long

        Liest nur Kanal 1 von Sensor 3074 für das letzte Jahr.

        .OUTPUTS
        PSCustomObject je Messzeitpunkt mit den Eigenschaften 'time' und je
        Kanal-ID, sofern nicht -Raw angegeben ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$SensorId,

        [Parameter()]
        [ValidateSet('Live', 'Short', 'Medium', 'Long')]
        [string]$TimeRange = 'Live',

        [Parameter()]
        [string[]]$ChannelId,

        [Parameter()]
        [switch]$Raw
    )

    process {
        $query = @{}
        if ($ChannelId) { $query['channels'] = $ChannelId }

        $type = $TimeRange.ToLower()
        $table = Invoke-PRTGRestMethod -Path "/experimental/timeseries/$SensorId/$type" -Method GET -QueryParameter $query

        if ($Raw -or -not $table -or $table.Count -lt 1) {
            return $table
        }

        # Erste Zeile = Header (z.B. 'time','1002.1','1002.2'), restliche Zeilen = Werte.
        $header = $table[0]
        for ($i = 1; $i -lt $table.Count; $i++) {
            $row = $table[$i]
            $obj = [ordered]@{}
            for ($col = 0; $col -lt $header.Count; $col++) {
                $obj[[string]$header[$col]] = $row[$col]
            }
            [pscustomobject]$obj
        }
    }
}
