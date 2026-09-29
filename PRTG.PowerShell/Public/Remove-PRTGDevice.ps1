function Remove-PRTGDevice {
    <#
        .SYNOPSIS
        Löscht ein Gerät inklusive aller untergeordneten Sensoren und Kanäle.

        .DESCRIPTION
        Remove-PRTGDevice führt einen DELETE-Aufruf gegen
        /experimental/devices/{id} aus. Dieser Vorgang ist NICHT umkehrbar:
        das Gerät und alle untergeordneten Sensoren/Kanäle samt ihrer
        historischen Monitoring-Daten werden endgültig entfernt.

        Aus diesem Grund implementiert dieses Cmdlet -Confirm/-WhatIf
        (SupportsShouldProcess) und fragt standardmäßig vor der Ausführung nach
        Bestätigung. Für automatisierte Skripte kann -Confirm:$false verwendet
        werden, sollte aber bewusst eingesetzt werden.

        .PARAMETER Id
        Objekt-ID des zu löschenden Geräts. Auch über die Pipeline entgegennehmbar,
        z.B. von Get-PRTGDevice.

        .EXAMPLE
        Remove-PRTGDevice -Id 2322

        Löscht das Gerät mit der ID 2322 nach Bestätigung durch den Anwender.

        .EXAMPLE
        Get-PRTGDevice -Filter 'name=@sub(TEST-)' | Remove-PRTGDevice -Confirm:$false

        Löscht alle Testgeräte, deren Name mit "TEST-" beginnt, ohne weitere
        Rückfrage (Vorsicht: nur für gut getestete Automatisierungs-Skripte).

        .OUTPUTS
        Keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('DeviceId')]
        [string[]]$Id
    )

    process {
        foreach ($deviceId in $Id) {
            if ($PSCmdlet.ShouldProcess("Gerät $deviceId", "Endgültig löschen (inkl. aller Sensoren/Kanäle)")) {
                Invoke-PRTGRestMethod -Path "/experimental/devices/$deviceId" -Method DELETE | Out-Null
            }
        }
    }
}
