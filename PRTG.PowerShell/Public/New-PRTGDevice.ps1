function New-PRTGDevice {
    <#
        .SYNOPSIS
        Erstellt ein neues Gerät in PRTG, untergeordnet zu einer Gruppe oder Probe.

        .DESCRIPTION
        New-PRTGDevice führt einen POST-Aufruf gegen
        /experimental/groups/{id}/device bzw. /experimental/probes/{id}/device
        aus, je nachdem, ob -ParentGroupId oder -ParentProbeId angegeben wird.

        .PARAMETER ParentGroupId
        Objekt-ID der Gruppe, unter der das neue Gerät angelegt werden soll.
        Schließt sich mit -ParentProbeId gegenseitig aus.

        .PARAMETER ParentProbeId
        Objekt-ID der Probe, unter der das neue Gerät angelegt werden soll.
        Schließt sich mit -ParentGroupId gegenseitig aus.

        .PARAMETER Name
        Anzeigename des neuen Geräts.

        .PARAMETER HostAddress
        IP-Adresse oder DNS-Name des neuen Geräts.

        .PARAMETER Settings
        Zusätzliche, rohe Settings-Struktur als Hashtable, die mit Name/Host
        zusammengeführt wird (z.B. für Tags oder Icon).

        .EXAMPLE
        New-PRTGDevice -ParentGroupId 1044 -Name 'Webserver-02' -HostAddress '10.0.10.22'

        Legt ein neues Gerät in der Gruppe 1044 an.

        .EXAMPLE
        New-PRTGDevice -ParentProbeId 1 -Name 'Switch-Keller' -HostAddress '10.0.0.5'

        Legt ein neues Gerät direkt unter der Probe mit der ID 1 an.

        .OUTPUTS
        PSCustomObject mit den Eigenschaften des neu erstellten Geräts.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Group')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Group')]
        [string]$ParentGroupId,

        [Parameter(Mandatory, ParameterSetName = 'Probe')]
        [string]$ParentProbeId,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$HostAddress,

        [Parameter()]
        [hashtable]$Settings
    )

    $body = @{}
    if ($Settings) { $body = $Settings.Clone() }
    if (-not $body.ContainsKey('basic')) { $body['basic'] = @{} }
    $body['basic']['name'] = $Name
    $body['basic']['host'] = $HostAddress

    $path = if ($PSCmdlet.ParameterSetName -eq 'Group') {
        "/experimental/groups/$ParentGroupId/device"
    }
    else {
        "/experimental/probes/$ParentProbeId/device"
    }

    $target = if ($PSCmdlet.ParameterSetName -eq 'Group') { "Gruppe $ParentGroupId" } else { "Probe $ParentProbeId" }

    if ($PSCmdlet.ShouldProcess($target, "Neues Gerät '$Name' ($HostAddress) anlegen")) {
        Invoke-PRTGRestMethod -Path $path -Method POST -Body $body
    }
}
