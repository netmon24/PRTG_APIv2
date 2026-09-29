function Set-PRTGGroup {
    <#
        .SYNOPSIS
        Ändert die Einstellungen einer bestehenden Gruppe in PRTG.

        .DESCRIPTION
        Set-PRTGGroup führt einen PATCH-Aufruf gegen /experimental/groups/{id}
        aus und aktualisiert damit Einstellungen einer Gruppe, analog zu
        Set-PRTGDevice.

        .PARAMETER Id
        Objekt-ID der zu ändernden Gruppe.

        .PARAMETER Name
        Neuer Anzeigename der Gruppe (entspricht 'basic.name').

        .PARAMETER Settings
        Vollständige, rohe Settings-Struktur als Hashtable für Felder ohne
        dedizierten Parameter.

        .PARAMETER PassThru
        Gibt das aktualisierte Gruppenobjekt zurück.

        .EXAMPLE
        Set-PRTGGroup -Id 1044 -Name 'Rechenzentrum Hannover'

        Benennt die Gruppe mit der ID 1044 um.

        .OUTPUTS
        Keine Ausgabe, sofern -PassThru nicht angegeben ist.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [string]$Id,

        [Parameter()]
        [string]$Name,

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

        if ($body.Count -eq 0) {
            Write-Warning "Set-PRTGGroup: Keine Änderungen angegeben (weder -Name noch -Settings). Es wurde nichts geändert."
            return
        }

        if ($PSCmdlet.ShouldProcess("Gruppe $Id", "Einstellungen aktualisieren")) {
            Invoke-PRTGRestMethod -Path "/experimental/groups/$Id" -Method PATCH -Body $body | Out-Null

            if ($PassThru) {
                Get-PRTGGroup -Id $Id
            }
        }
    }
}
