function Get-PRTGSensorStatusSummary {
    <#
        .SYNOPSIS
        Liefert eine globale Zusammenfassung aller Sensor-Zustände in PRTG.

        .DESCRIPTION
        Ruft GET /sensor-status-summary auf und liefert eine Übersicht, wie viele
        Sensoren sich in welchem Status befinden (z.B. Up, Down, Warning, Paused).
        Nützlich für Dashboards oder schnelle Health-Checks per Skript.

        .EXAMPLE
        Get-PRTGSensorStatusSummary

        Zeigt die aktuelle Verteilung aller Sensor-Zustände im System.

        .OUTPUTS
        PSCustomObject mit den Zählern je Sensor-Status.
    #>
    [CmdletBinding()]
    param()

    Invoke-PRTGRestMethod -Path '/sensor-status-summary' -Method GET
}
