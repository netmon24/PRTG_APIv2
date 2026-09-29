function Set-PRTGDevice {
    <#
        .SYNOPSIS
        Ändert die Einstellungen eines bestehenden Geräts in PRTG.

        .DESCRIPTION
        Set-PRTGDevice führt einen PATCH-Aufruf gegen /devices/{id} aus und
        aktualisiert damit Einstellungen eines Geräts. Die PRTG API v2 erwartet
        die zu ändernden Werte gruppiert nach Settings-Abschnitt (z.B. 'basic'
        für Name/Tags, 'host' für Adresse). Über -Settings kann eine beliebige,
        vollständige Hashtable-Struktur übergeben werden; für die häufigsten
        Felder (Name, Host, Tags) stehen zusätzlich bequeme Parameter zur
        Verfügung, die intern automatisch in die passende Struktur übersetzt
        werden.

        .PARAMETER Id
        Objekt-ID des zu ändernden Geräts.

        .PARAMETER Name
        Neuer Anzeigename des Geräts (entspricht 'basic.name').

        .PARAMETER HostAddress
        Neue IP-Adresse oder DNS-Name des Geräts (entspricht 'host.host' bzw.
        je PRTG-Version 'basic.host').

        .PARAMETER Settings
        Vollständige, rohe Settings-Struktur als Hashtable, falls Felder
        geändert werden sollen, für die es keinen dedizierten Parameter gibt,
        z.B. @{ basic = @{ name = 'Neuer Name'; tags = @('Hannover','Core') } }.
        Wird mit den übrigen Parametern zusammengeführt, falls beide angegeben
        werden.

        .PARAMETER PassThru
        Gibt das aktualisierte Geräteobjekt zurück (führt dazu einen zusätzlichen
        Get-PRTGDevice-Aufruf aus, da PATCH selbst nur den Status 204 liefert).

        .EXAMPLE
        Set-PRTGDevice -Id 2322 -Name 'Webserver-Hannover-01'

        Benennt das Gerät mit der ID 2322 um.

        .EXAMPLE
        Set-PRTGDevice -Id 2322 -Settings @{ basic = @{ tags = @('Produktion','Web') } } -PassThru

        Setzt eigene Tags über die rohe Settings-Struktur und gibt das
        aktualisierte Objekt zurück.

        .OUTPUTS
        Keine Ausgabe, sofern -PassThru nicht angegeben ist.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('DeviceId')]
        [string]$Id,

        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$HostAddress,

        [Parameter()]
        [hashtable]$Settings,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $body = @{}
        if ($Settings) { $body = $Settings.Clone() }

        if ($Name) {
            if (-not $body.ContainsKey('basic')) { $body['basic'] = @{} }
            $body['basic']['name'] = $Name
        }
        if ($HostAddress) {
            if (-not $body.ContainsKey('basic')) { $body['basic'] = @{} }
            $body['basic']['host'] = $HostAddress
        }

        if ($body.Count -eq 0) {
            Write-Warning "Set-PRTGDevice: Keine Änderungen angegeben (weder -Name, -HostAddress noch -Settings). Es wurde nichts geändert."
            return
        }

        if ($PSCmdlet.ShouldProcess("Gerät $Id", "Einstellungen aktualisieren")) {
            Invoke-PRTGRestMethod -Path "/devices/$Id" -Method PATCH -Body $body | Out-Null

            if ($PassThru) {
                Get-PRTGDevice -Id $Id
            }
        }
    }
}
