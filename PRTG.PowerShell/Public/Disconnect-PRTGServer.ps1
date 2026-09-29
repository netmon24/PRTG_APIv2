function Disconnect-PRTGServer {
    <#
        .SYNOPSIS
        Trennt die aktive Verbindung zu einem PRTG-Core-Server.

        .DESCRIPTION
        Entfernt das im Modul-Speicher gehaltene Bearer-Token und beendet damit
        die aktive PowerShell-Sitzung zur PRTG API v2. Ein erneuter Aufruf eines
        beliebigen anderen Cmdlets dieses Moduls erfordert danach einen erneuten
        Connect-PRTGServer.

        .EXAMPLE
        Disconnect-PRTGServer

        Trennt die aktuelle Verbindung.
    #>
    [CmdletBinding()]
    param()

    Clear-PRTGSession
    Write-Verbose "PRTG-Sitzung wurde beendet."
}
