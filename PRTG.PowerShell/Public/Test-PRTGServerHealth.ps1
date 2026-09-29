function Test-PRTGServerHealth {
    <#
        .SYNOPSIS
        Prüft, ob der PRTG-Application-Server erreichbar und betriebsbereit ist.

        .DESCRIPTION
        Test-PRTGServerHealth ruft GET /health auf. Dieser Endpunkt erfordert
        keine Authentifizierung im eigentlichen Sinn der übrigen Endpunkte,
        wird aber über die bestehende Sitzung (BaseUri/Zertifikatseinstellungen)
        abgefragt. Liefert $true zurück, wenn der Server erreichbar und die
        Lizenz aktiv ist, sonst $false (mit einer erläuternden Warnung).

        .EXAMPLE
        Test-PRTGServerHealth

        Prüft den Zustand des verbundenen PRTG-Servers.

        .OUTPUTS
        Boolean.
    #>
    [CmdletBinding()]
    param()

    try {
        Invoke-PRTGRestMethod -Path '/health' -Method GET | Out-Null
        return $true
    }
    catch {
        Write-Warning "PRTG-Server nicht erreichbar oder Lizenz inaktiv: $($_.Exception.Message)"
        return $false
    }
}
