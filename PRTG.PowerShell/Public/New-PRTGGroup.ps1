function New-PRTGGroup {
    <#
        .SYNOPSIS
        Erstellt eine neue Gruppe in PRTG, untergeordnet zu einer Gruppe oder Probe.

        .DESCRIPTION
        New-PRTGGroup führt einen POST-Aufruf gegen
        /experimental/groups/{id}/group bzw. /experimental/probes/{id}/group
        aus, je nachdem, ob -ParentGroupId oder -ParentProbeId angegeben wird.

        .PARAMETER ParentGroupId
        Objekt-ID der übergeordneten Gruppe. Schließt sich mit -ParentProbeId
        gegenseitig aus.

        .PARAMETER ParentProbeId
        Objekt-ID der Probe, unter der die neue Gruppe angelegt werden soll.
        Schließt sich mit -ParentGroupId gegenseitig aus.

        .PARAMETER Name
        Anzeigename der neuen Gruppe.

        .PARAMETER Settings
        Zusätzliche, rohe Settings-Struktur als Hashtable.

        .EXAMPLE
        New-PRTGGroup -ParentProbeId 1 -Name 'Hannover - Rechenzentrum'

        Legt eine neue Gruppe direkt unter der lokalen Probe an.

        .EXAMPLE
        New-PRTGGroup -ParentGroupId 1044 -Name 'Webserver'

        Legt eine neue Untergruppe innerhalb der Gruppe 1044 an.

        .OUTPUTS
        PSCustomObject mit den Eigenschaften der neu erstellten Gruppe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Group')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Group')]
        [string]$ParentGroupId,

        [Parameter(Mandatory, ParameterSetName = 'Probe')]
        [string]$ParentProbeId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Settings
    )

    $body = @{}
    if ($Settings) { $body = $Settings.Clone() }
    if (-not $body.ContainsKey('basic')) { $body['basic'] = @{} }
    $body['basic']['name'] = $Name

    $path = if ($PSCmdlet.ParameterSetName -eq 'Group') {
        "/experimental/groups/$ParentGroupId/group"
    }
    else {
        "/experimental/probes/$ParentProbeId/group"
    }

    $target = if ($PSCmdlet.ParameterSetName -eq 'Group') { "Gruppe $ParentGroupId" } else { "Probe $ParentProbeId" }

    if ($PSCmdlet.ShouldProcess($target, "Neue Gruppe '$Name' anlegen")) {
        Invoke-PRTGRestMethod -Path $path -Method POST -Body $body
    }
}
