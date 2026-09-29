function Get-PRTGObjectCount {
    <#
        .SYNOPSIS
        Liefert eine Übersicht, wie viele Objekte je Typ (Probes, Gruppen, Geräte,
        Sensoren, ...) in PRTG existieren.

        .DESCRIPTION
        Ruft GET /objects/count auf. Praktisch für eine schnelle Bestandsübersicht,
        z.B. im Rahmen von Lizenz- oder Kapazitätsprüfungen.

        .EXAMPLE
        Get-PRTGObjectCount

        Zeigt die Gesamtanzahl je Objekttyp.

        .OUTPUTS
        PSCustomObject mit den Zählern je Objekttyp.
    #>
    [CmdletBinding()]
    param()

    Invoke-PRTGRestMethod -Path '/objects/count' -Method GET
}
