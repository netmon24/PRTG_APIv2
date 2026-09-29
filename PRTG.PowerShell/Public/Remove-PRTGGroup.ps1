function Remove-PRTGGroup {
    <#
        .SYNOPSIS
        Löscht eine Gruppe inklusive aller untergeordneten Gruppen und Geräte.

        .DESCRIPTION
        Remove-PRTGGroup führt einen DELETE-Aufruf gegen
        /experimental/groups/{id} aus. Dieser Vorgang ist NICHT umkehrbar
        und entfernt rekursiv alle untergeordneten Objekte (Untergruppen,
        Geräte, Sensoren, Kanäle) samt ihrer historischen Daten.

        .PARAMETER Id
        Objekt-ID der zu löschenden Gruppe. Auch über die Pipeline entgegennehmbar.

        .EXAMPLE
        Remove-PRTGGroup -Id 1044

        Löscht die Gruppe mit der ID 1044 nach Bestätigung durch den Anwender.

        .OUTPUTS
        Keine Ausgabe.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('GroupId')]
        [string[]]$Id
    )

    process {
        foreach ($groupId in $Id) {
            if ($PSCmdlet.ShouldProcess("Gruppe $groupId", "Endgültig löschen (inkl. aller Untergruppen/Geräte/Sensoren)")) {
                Invoke-PRTGRestMethod -Path "/experimental/groups/$groupId" -Method DELETE | Out-Null
            }
        }
    }
}
