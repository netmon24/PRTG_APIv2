function Get-PRTGPagedResult {
    <#
        .SYNOPSIS
        Interne Funktion. Ruft einen Listen-Endpunkt der PRTG API v2 vollständig ab
        und kümmert sich dabei automatisch um Paging (offset/limit).

        .DESCRIPTION
        Die PRTG API v2 begrenzt die Anzahl der pro Aufruf zurückgegebenen Objekte
        (Standard meist 100, Maximum 3000). Diese Funktion ruft den angegebenen
        Pfad wiederholt mit steigendem 'offset' auf, bis keine weiteren Ergebnisse
        mehr zurückkommen oder die vom Anwender angeforderte Obergrenze (-First)
        erreicht ist.

        .PARAMETER Path
        API-Pfad, z.B. '/experimental/devices'.

        .PARAMETER QueryParameter
        Zusätzliche, feste Query-Parameter (z.B. filter, include, sort_by).
        'offset' und 'limit' werden von dieser Funktion selbst verwaltet und sollten
        hier NICHT übergeben werden.

        .PARAMETER PageSize
        Anzahl der Objekte pro Einzelaufruf. Standard: 500.

        .PARAMETER First
        Maximale Gesamtanzahl an Objekten, die zurückgegeben werden sollen.
        Ohne Angabe werden alle verfügbaren Objekte abgerufen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [hashtable]$QueryParameter = @{},

        [Parameter()]
        [int]$PageSize = 500,

        [Parameter()]
        [int]$First = 0
    )

    $offset  = 0
    $results = [System.Collections.Generic.List[object]]::new()

    while ($true) {
        $remaining = if ($First -gt 0) { $First - $results.Count } else { $PageSize }
        if ($First -gt 0 -and $remaining -le 0) { break }

        $effectiveLimit = if ($First -gt 0 -and $remaining -lt $PageSize) { $remaining } else { $PageSize }

        $query = $QueryParameter.Clone()
        $query['offset'] = $offset
        $query['limit']  = $effectiveLimit

        $page = Invoke-PRTGRestMethod -Path $Path -Method GET -QueryParameter $query

        if (-not $page -or @($page).Count -eq 0) { break }

        foreach ($item in @($page)) { $results.Add($item) }

        if (@($page).Count -lt $effectiveLimit) { break }
        $offset += $effectiveLimit
    }

    return $results
}
