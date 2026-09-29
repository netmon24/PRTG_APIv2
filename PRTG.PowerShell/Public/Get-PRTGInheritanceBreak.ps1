function Get-PRTGInheritanceBreak {
    <#
        .SYNOPSIS
        Findet Objekte im PRTG-Baum, bei denen die Einstellungsvererbung
        unterbrochen wurde.

        .DESCRIPTION
        In PRTG werden viele Einstellungsbereiche (z.B. Benachrichtigungen,
        Zugriffsrechte, Scan-Intervall, Kanal-Limits) standardmäßig von
        übergeordneten Objekten (Root, Probe, Gruppe, Gerät) vererbt. Wird diese
        Vererbung für ein Objekt gezielt aufgehoben ("Click to interrupt the
        inheritance" in der Weboberfläche), gilt ab diesem Punkt im Baum eine
        eigene, abweichende Einstellung - ein häufiger, aber leicht übersehener
        Grund dafür, warum zentrale Änderungen (z.B. an der Root-Gruppe) bei
        einzelnen Objekten nicht ankommen.

        Dieses Cmdlet fragt die PRTG API v2 mit dem Include-Parameter
        'inheritance' ab (zusammen mit 'all_sections', da 'inheritance' laut
        API-Dokumentation nur in Kombination mit einem weiteren Include-Wert
        verwendet werden kann) und durchsucht die zurückgegebenen
        Einstellungsbereiche jedes Objekts nach Abschnitten, die als NICHT
        vererbt markiert sind. Da dieser Teil der PRTG API v2 laut Paessler
        noch nicht vollständig stabil ist, wertet das Cmdlet das Ergebnis
        bewusst generisch aus (Suche nach typischen Feldnamen wie 'inherited',
        'is_inherited' oder 'inheritance' mit Wert false/False in beliebiger
        Verschachtelungstiefe) statt sich auf ein einzelnes, festes Schema zu
        verlassen.

        .PARAMETER ObjectType
        Einzuschließende Objekttypen: 'Device', 'Group', 'Probe' oder 'All'
        (Standard). Sensoren werden bewusst nicht standardmäßig eingeschlossen,
        da Vererbungsbrüche auf Sensor-Ebene sehr häufig und meist beabsichtigt
        sind (jeder Sensor kann z.B. eigene Kanal-Limits haben); mit
        -IncludeSensors lassen sie sich optional ergänzen.

        .PARAMETER IncludeSensors
        Bezieht zusätzlich Sensoren in die Prüfung ein.

        .PARAMETER Filter
        Optionaler zusätzlicher PRTG-API-Filterausdruck, um die Suche
        einzuschränken, z.B. auf eine bestimmte Gruppe oder einen Tag.

        .PARAMETER Sections
        Einschränkung auf bestimmte Einstellungsbereiche statt aller
        Bereiche, z.B. 'accessrightsgroup' (Zugriffsrechte) oder
        'notifyconfig' (Benachrichtigungen). Ohne Angabe werden alle
        Bereiche über 'all_sections' abgefragt.

        .EXAMPLE
        Get-PRTGInheritanceBreak

        Listet alle Gruppen, Geräte und Probes auf, bei denen mindestens ein
        Einstellungsbereich nicht mehr vom übergeordneten Objekt erbt.

        .EXAMPLE
        Get-PRTGInheritanceBreak -ObjectType Device -IncludeSensors

        Prüft sowohl Geräte als auch Sensoren auf unterbrochene Vererbung.

        .EXAMPLE
        Get-PRTGInheritanceBreak -Sections accessrightsgroup

        Prüft gezielt nur den Bereich "Zugriffsrechte" auf Vererbungsbrüche -
        nützlich, um z.B. herauszufinden, wo abweichende Berechtigungen
        gesetzt wurden.

        .OUTPUTS
        PSCustomObject je gefundenem Vererbungsbruch mit den Eigenschaften:
        Id, Name, Type, BrokenSection, Path (sofern verfügbar).

        .NOTES
        Der Include-Parameter 'inheritance' ist Teil der PRTG API v2 und laut
        Paessler-Dokumentation noch nicht vollständig stabil/feature-complete.
        Sollte sich das genaue Antwortformat in einer künftigen PRTG-Version
        ändern, kann es nötig sein, die interne Erkennungslogik in diesem
        Cmdlet anzupassen.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Device', 'Group', 'Probe', 'All')]
        [string]$ObjectType = 'All',

        [Parameter()]
        [switch]$IncludeSensors,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string[]]$Sections
    )

    # Welche Include-Werte für die Settings-Bereiche angefordert werden:
    # entweder die vom Anwender gewünschten konkreten Bereiche, oder pauschal
    # 'all_sections' für wirklich alle verfügbaren Bereiche.
    $sectionInclude = if ($Sections) { $Sections } else { @('all_sections') }
    $includeValues  = @($sectionInclude) + @('inheritance')

    # Zu prüfende Objekttypen anhand der Parameter zusammenstellen.
    $typesToCheck = switch ($ObjectType) {
        'All'    { @('group', 'device', 'probe') }
        default  { @($ObjectType.ToLower()) }
    }
    if ($IncludeSensors) { $typesToCheck += 'sensor' }

    # Baut den Filterausdruck für einen einzelnen Objekttyp, kombiniert mit
    # einem optionalen zusätzlichen Filter des Anwenders.
    function Get-TypeFilter {
        param([string]$Type)
        if ($Filter) { return "type=$Type;$Filter" }
        return "type=$Type"
    }

    # Durchsucht ein beliebig verschachteltes Objekt rekursiv nach Feldern,
    # die typischerweise eine NICHT vererbte Einstellung kennzeichnen, und
    # gibt die Namen der betroffenen Settings-Bereiche zurück.
    function Find-BrokenSections {
        param(
            [Parameter(Mandatory)]
            [object]$Node,

            [Parameter()]
            [string]$CurrentSection = $null
        )

        $broken = [System.Collections.Generic.List[string]]::new()

        if ($null -eq $Node) { return $broken }

        if ($Node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $Node.PSObject.Properties) {
                $propName  = $prop.Name
                $propValue = $prop.Value

                # Auf oberster Verschachtelungsebene entspricht der Property-Name
                # häufig dem Settings-Bereich selbst (z.B. 'alerting', 'intervalgroup').
                $sectionForChild = if ($CurrentSection) { $CurrentSection } else { $propName }

                $isInheritanceFlag = $propName -in @('inherited', 'is_inherited', 'inheritance', 'isinherited')
                $isFalseValue      = ($propValue -eq $false) -or ("$propValue" -ieq 'false')

                if ($isInheritanceFlag -and $isFalseValue) {
                    if ($sectionForChild -and ($broken -notcontains $sectionForChild)) {
                        $broken.Add($sectionForChild)
                    }
                }
                elseif ($propValue -is [System.Management.Automation.PSCustomObject] -or $propValue -is [System.Collections.IEnumerable] -and $propValue -isnot [string]) {
                    foreach ($found in (Find-BrokenSections -Node $propValue -CurrentSection $sectionForChild)) {
                        if ($broken -notcontains $found) { $broken.Add($found) }
                    }
                }
            }
        }
        elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
            foreach ($item in $Node) {
                foreach ($found in (Find-BrokenSections -Node $item -CurrentSection $CurrentSection)) {
                    if ($broken -notcontains $found) { $broken.Add($found) }
                }
            }
        }

        return $broken
    }

    foreach ($type in $typesToCheck) {
        $query = @{
            filter  = (Get-TypeFilter -Type $type)
            include = $includeValues
        }

        $objects = Get-PRTGPagedResult -Path '/experimental/objects' -QueryParameter $query

        foreach ($obj in $objects) {
            $brokenSections = Find-BrokenSections -Node $obj

            foreach ($section in $brokenSections) {
                [pscustomobject]@{
                    Id            = $obj.id
                    Name          = $obj.name
                    Type          = $type
                    BrokenSection = $section
                    Path          = if ($obj.path) { ($obj.path | ForEach-Object { $_.name }) -join ' > ' } else { $null }
                    Href          = $obj.href
                }
            }
        }
    }
}
