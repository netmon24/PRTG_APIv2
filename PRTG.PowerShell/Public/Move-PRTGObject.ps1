function Move-PRTGObject {
    <#
        .SYNOPSIS
        Verschiebt ein Monitoring-Objekt innerhalb seiner Geschwisterobjekte oder
        zu einem neuen übergeordneten Objekt.

        .DESCRIPTION
        Move-PRTGObject führt einen POST-Aufruf gegen /objects/{id}/move aus.
        Es kann entweder die Position innerhalb der aktuellen Geschwisterobjekte
        geändert werden (per fester Position oder per Preset 'top'/'up'/'down'/
        'bottom') oder das Objekt zu einem komplett neuen Elternobjekt
        verschoben werden (mit optional zusätzlicher Zielposition).

        .PARAMETER Id
        Objekt-ID des zu verschiebenden Objekts (Gerät, Gruppe, Sensor, ...).

        .PARAMETER NewParentId
        Objekt-ID des neuen übergeordneten Objekts. Wenn nicht angegeben, bleibt
        das Objekt unter seinem aktuellen Elternobjekt und nur seine Position
        ändert sich.

        .PARAMETER Position
        Absolute Zielposition innerhalb der Geschwisterobjekte. Muss ein
        Vielfaches von 10 sein (PRTG-interne Sortierschrittweite), z.B. 10, 20, 30.

        .PARAMETER PositionPreset
        Schnellauswahl für die Position: 'Top', 'Up', 'Down' oder 'Bottom'.
        Schließt sich mit -Position gegenseitig aus.

        .EXAMPLE
        Move-PRTGObject -Id 2322 -NewParentId 1044

        Verschiebt das Objekt 2322 unter das neue Elternobjekt 1044.

        .EXAMPLE
        Move-PRTGObject -Id 2322 -PositionPreset Top

        Verschiebt das Objekt 2322 an die erste Position innerhalb seiner
        aktuellen Geschwisterobjekte.

        .OUTPUTS
        Keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter()]
        [string]$NewParentId,

        [Parameter(ParameterSetName = 'Position')]
        [ValidateScript({
            if ($_ % 10 -ne 0) { throw "Position muss ein Vielfaches von 10 sein (z.B. 10, 20, 30)." }
            $true
        })]
        [int]$Position,

        [Parameter(ParameterSetName = 'Preset')]
        [ValidateSet('Top', 'Up', 'Down', 'Bottom')]
        [string]$PositionPreset
    )

    process {
        $body = @{}
        if ($NewParentId)    { $body['parent'] = $NewParentId }
        if ($PSBoundParameters.ContainsKey('Position')) { $body['position'] = $Position }
        if ($PositionPreset) { $body['position_preset'] = $PositionPreset.ToLower() }

        if ($body.Count -eq 0) {
            Write-Warning "Move-PRTGObject: Weder -NewParentId, -Position noch -PositionPreset angegeben. Es wurde nichts verschoben."
            return
        }

        if ($PSCmdlet.ShouldProcess("Objekt $Id", "Verschieben")) {
            Invoke-PRTGRestMethod -Path "/objects/$Id/move" -Method POST -Body $body | Out-Null
        }
    }
}
