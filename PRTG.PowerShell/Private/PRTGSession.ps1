#region Modul-weiter Session-Speicher
# Dieses Skript hält den aktuellen PRTG-Verbindungskontext im Speicher des Moduls.
# Der Kontext wird durch Connect-PRTGServer gesetzt und von allen Public-Cmdlets
# über Get-PRTGSession gelesen, damit der Anwender Server/Token nicht bei jedem
# Aufruf erneut angeben muss.

# Script-Scope-Variable: nur innerhalb dieses Moduls sichtbar (nicht im globalen Scope).
$script:PRTGSession = $null

function Set-PRTGSession {
    <#
        .SYNOPSIS
        Interne Funktion. Speichert das aktive Verbindungsobjekt im Modul-Scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Session
    )
    $script:PRTGSession = $Session
}

function Get-PRTGSession {
    <#
        .SYNOPSIS
        Interne Funktion. Liefert das aktive Verbindungsobjekt oder wirft einen Fehler,
        wenn noch keine Verbindung mit Connect-PRTGServer aufgebaut wurde.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:PRTGSession) {
        throw "Es besteht keine aktive PRTG-Verbindung. Führen Sie zuerst 'Connect-PRTGServer' aus."
    }
    return $script:PRTGSession
}

function Clear-PRTGSession {
    <#
        .SYNOPSIS
        Interne Funktion. Entfernt das aktive Verbindungsobjekt (genutzt von Disconnect-PRTGServer).
    #>
    [CmdletBinding()]
    param()
    $script:PRTGSession = $null
}
#endregion
