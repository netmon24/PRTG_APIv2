function New-PRTGChildObject {
    <#
        .SYNOPSIS
        Interne Funktion. Legt ein Objekt unterhalb eines Elternobjekts an und
        erklärt ein 404, statt es weiterzureichen.

        .DESCRIPTION
        Die Anlege-Endpunkte von PRTG antworten mit "404 Not Found", wenn die
        Eltern-ID nicht existiert, wenn sie auf einen anderen Objekttyp zeigt
        (eine Gruppen-ID als -ParentProbeId) und wenn der Server die Kombination
        aus Eltern- und Kindtyp gar nicht anbietet. Alle drei Fälle sehen
        gleich aus und lesen sich wie ein fehlender Endpunkt, obwohl in zwei von
        drei Fällen nur ein Parameter falsch gewählt ist.

        Diese Funktion führt den POST aus und fragt nach einem 404 beim Server
        nach, was das Elternobjekt tatsächlich ist. Die Ausnahme nennt danach
        die Ursache und den Parameter, der gemeint war.

        .PARAMETER Path
        API-Pfad des Anlege-Aufrufs, z.B. '/experimental/groups/1044/device'.

        .PARAMETER Body
        Request-Body des Anlege-Aufrufs.

        .PARAMETER ParentId
        Objekt-ID des Elternobjekts, wie der Aufrufer sie übergeben hat.

        .PARAMETER ExpectedParentKind
        Objekttyp, den der gewählte Parameter voraussetzt: 'group' oder 'probe'.

        .PARAMETER ChildKind
        Was angelegt werden soll: 'group' oder 'device'. Bestimmt nur den
        Hinweistext.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Body,

        [Parameter(Mandatory)]
        [string]$ParentId,

        [Parameter(Mandatory)]
        [ValidateSet('group', 'probe')]
        [string]$ExpectedParentKind,

        [Parameter(Mandatory)]
        [ValidateSet('group', 'device')]
        [string]$ChildKind
    )

    try {
        return Invoke-PRTGRestMethod -Path $Path -Method POST -Body $Body
    }
    catch {
        $status = $null
        if ($_.Exception.Data -and $_.Exception.Data.Contains('StatusCode')) {
            $status = $_.Exception.Data['StatusCode']
        }

        # Nur das 404 ist mehrdeutig. Alles andere - 400 wegen eines ungültigen
        # Feldes, 401, 403, 500 - sagt bereits, was es sagen will.
        if ($status -ne 404) { throw }

        # Nachsehen, was unter der ID wirklich liegt. Der erste Endpunkt, der ein
        # Objekt liefert, gewinnt; dessen eigenes Feld "kind" ist die Auskunft,
        # nicht der Endpunkt, über den es gefunden wurde.
        $parent = $null
        foreach ($lookup in '/groups', '/probes', '/devices') {
            try {
                $parent = Invoke-PRTGRestMethod -Path "$lookup/$ParentId" -Method GET
                if ($parent) { break }
            }
            catch { }
        }

        $kindLabel = @{
            probe  = 'eine Probe'
            group  = 'eine Gruppe'
            device = 'ein Gerät'
            sensor = 'ein Sensor'
        }
        # Drei Beugungen desselben Wortes, damit die Meldungen lesbar bleiben.
        $childGenitive = if ($ChildKind -eq 'group') { 'der Gruppe' } else { 'des Geräts' }
        $childNegated  = if ($ChildKind -eq 'group') { 'keine Gruppe' } else { 'kein Gerät' }
        $expectedLabel = if ($ExpectedParentKind -eq 'group') { 'eine Gruppe' } else { 'eine Probe' }

        if (-not $parent) {
            throw "Unter der ID $ParentId ist kein Objekt auffindbar - der Server kennt dort weder Probe noch Gruppe noch Gerät. Deshalb das 404 beim Anlegen $childGenitive. Prüfen Sie die ID im PRTG-Baum."
        }

        $actualKind = "$($parent.kind)".ToLower()
        $actualName = "$($parent.name)"

        if ($actualKind -and $actualKind -ne $ExpectedParentKind) {
            $label = if ($kindLabel.ContainsKey($actualKind)) { $kindLabel[$actualKind] } else { "vom Typ '$actualKind'" }
            $message = "Objekt $ParentId ist $label ('$actualName'), erwartet wurde $expectedLabel."

            if ($actualKind -eq 'group' -and $ChildKind -in @('group', 'device')) {
                $message += " Verwenden Sie -ParentGroupId $ParentId."
            }
            elseif ($actualKind -eq 'probe' -and $ChildKind -eq 'group') {
                $message += " Verwenden Sie -ParentProbeId $ParentId."
            }
            else {
                $message += " Unterhalb dieses Objekttyps lässt sich $childNegated anlegen."
            }

            throw $message
        }

        # Der Elterntyp passt, der Endpunkt existiert trotzdem nicht.
        $message = "Objekt $ParentId ist tatsächlich $expectedLabel ('$actualName'), der Server kennt aber keinen Endpunkt 'POST $Path'."
        if ($ChildKind -eq 'device' -and $ExpectedParentKind -eq 'probe') {
            $message += " Die API v2 sieht Geräte nur unterhalb von Gruppen vor. Legen Sie mit New-PRTGGroup -ParentProbeId $ParentId eine Gruppe an und nutzen Sie für das Gerät -ParentGroupId."
        }
        else {
            $message += " Möglicherweise bietet diese PRTG-Version den experimentellen Endpunkt noch nicht an."
        }
        throw $message
    }
}
