function Connect-PRTGServer {
    <#
        .SYNOPSIS
        Baut eine Verbindung zu einer PRTG-Core-Server-Instanz auf (PRTG API v2).

        .DESCRIPTION
        Connect-PRTGServer authentifiziert sich gegen die PRTG API v2 und speichert
        das resultierende Bearer-Token für die Dauer der PowerShell-Sitzung. Alle
        anderen Cmdlets dieses Moduls (Get-, New-, Set-, Remove-, Pause-, Resume-, ...)
        verwenden diese gespeicherte Sitzung automatisch.

        Es werden zwei Authentifizierungsarten unterstützt:

          1. API-Key (empfohlen, primärer Weg)
             Ein in PRTG unter "Setup > Account Settings > API Keys" erzeugter
             Schlüssel wird direkt als Bearer-Token verwendet. Es ist kein
             zusätzlicher Login-Request notwendig.

          2. Benutzername/Passwort (Fallback, Session-Login)
             Falls kein API-Key vorliegt (z.B. lokale Tests, Notfallzugriff),
             kann sich das Modul mit Benutzername/Passwort über den
             POST /session Endpunkt anmelden. PRTG liefert dabei ein
             session-gebundenes Token zurück, das wie ein API-Key verwendet wird.

        .PARAMETER ComputerName
        Hostname oder IP-Adresse des PRTG-Core-Servers, z.B. 'prtg.example.com'.
        Ohne Protokoll- oder Port-Angabe.

        .PARAMETER Port
        TCP-Port der PRTG API v2. Standard: 1616 (HTTPS).

        Die API v2 wird vom PRTG Application Server bedient, NICHT vom
        klassischen Webserver. Standardports sind 1616 (HTTPS) und 1615 (HTTP).
        Auf dem klassischen Port (443 bzw. 8443) antworten alle /api/v2-Pfade
        mit 302 auf die Loginseite, und ein Bearer-Header ergibt
        "401 Unsupported authorization scheme" - die Fehlermeldungen deuten
        dabei irreführend auf TLS-Probleme hin.

        Hinweis: Bis Version 1.0.0 war der Standard 443. Skripte, die sich
        darauf verlassen haben, müssen den Port nun explizit angeben.

        .PARAMETER UseHttp
        Schaltet auf unverschlüsseltes HTTP um (nicht empfohlen, nur für Testzwecke
        in vertrauenswürdigen Netzen).

        .PARAMETER ApiToken
        Der API-Key aus PRTG (Setup > Account Settings > API Keys). Wird als
        SecureString übergeben, um versehentliches Klartext-Logging zu vermeiden.
        Dies ist der primäre, empfohlene Authentifizierungsweg.

        .PARAMETER Credential
        PSCredential mit Benutzername/Passwort eines PRTG-Benutzerkontos. Wird nur
        verwendet, wenn kein -ApiToken angegeben wird (Fallback). Das Modul meldet
        sich damit über den Session-Login-Endpunkt an.

        .PARAMETER SkipCertificateCheck
        Überspringt die Validierung des TLS-Zertifikats des PRTG-Servers. Nützlich
        bei selbstsignierten Zertifikaten oder während eines Zertifikatswechsels
        (z.B. Migration auf Let's Encrypt). Für den produktiven Dauerbetrieb sollte
        stattdessen ein gültiges, vertrauenswürdiges Zertifikat installiert werden.

        .PARAMETER PassThru
        Gibt das Sitzungsobjekt zusätzlich auf der Konsole zurück.

        .EXAMPLE
        $token = Read-Host -AsSecureString -Prompt 'PRTG API-Key'
        Connect-PRTGServer -ComputerName 'prtg.example.com' -ApiToken $token

        Verbindet sich mittels API-Key über den Standardport 1616 (Standardweg, empfohlen).

        .EXAMPLE
        Connect-PRTGServer -ComputerName 'prtg.example.com' -Credential (Get-Credential) -SkipCertificateCheck

        Verbindet sich per Benutzername/Passwort (Fallback) und ignoriert dabei
        Zertifikatsfehler, z.B. während eines laufenden Zertifikatswechsels.

        .OUTPUTS
        PSCustomObject (nur bei -PassThru). Enthält BaseUri, AuthMethod und TokenExpiry.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ApiToken')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 1616,

        [Parameter()]
        [switch]$UseHttp,

        [Parameter(Mandatory, ParameterSetName = 'ApiToken')]
        [System.Security.SecureString]$ApiToken,

        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [switch]$SkipCertificateCheck,

        [Parameter()]
        [switch]$PassThru
    )

    $scheme  = if ($UseHttp) { 'http' } else { 'https' }
    $baseUri = "{0}://{1}:{2}" -f $scheme, $ComputerName, $Port

    # Sitzungsobjekt vorab aufbauen (ohne Token), damit Invoke-PRTGRestMethod
    # während des Login-Requests bereits SkipCertificateCheck respektieren kann.
    $tempSession = [pscustomobject]@{
        BaseUri              = $baseUri
        ApiToken             = $null
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        AuthMethod           = $null
    }

    switch ($PSCmdlet.ParameterSetName) {

        'ApiToken' {
            # Primärer Weg: API-Key wird 1:1 als Bearer-Token verwendet.
            $plainToken          = [System.Net.NetworkCredential]::new('', $ApiToken).Password
            $tempSession.ApiToken    = $plainToken
            $tempSession.AuthMethod  = 'ApiKey'
        }

        'Credential' {
            # Fallback-Weg: Login über POST /session mit Benutzername/Passwort.
            # PRTG liefert dabei ein temporäres, session-gebundenes Token zurück.
            Set-PRTGSession -Session $tempSession

            $plainPassword = $Credential.GetNetworkCredential().Password
            $loginBody     = @{
                username = $Credential.UserName
                password = $plainPassword
            }

            Write-Verbose "Melde mich per Benutzername/Passwort (Fallback) an: $($Credential.UserName)"

            try {
                $response = Invoke-PRTGRestMethod -Path '/session' -Method POST -Body $loginBody
            }
            catch {
                Clear-PRTGSession
                throw "Anmeldung mit Benutzername/Passwort fehlgeschlagen: $($_.Exception.Message)"
            }

            # Die API liefert je nach PRTG-Version das Token entweder direkt als
            # String-Eigenschaft 'token'/'access_token' oder verschachtelt zurück.
            $sessionToken = $response.token
            if (-not $sessionToken) { $sessionToken = $response.access_token }
            if (-not $sessionToken) { $sessionToken = $response }

            if (-not $sessionToken) {
                Clear-PRTGSession
                throw "Die Anmeldung war erfolgreich, aber es konnte kein Sitzungstoken aus der Antwort gelesen werden."
            }

            $tempSession.ApiToken   = $sessionToken
            $tempSession.AuthMethod = 'Credential'
        }
    }

    Set-PRTGSession -Session $tempSession

    # Verbindung verifizieren: /health liefert 204, wenn der Core-Server erreichbar
    # und lizenziert ist. Schlägt der Aufruf fehl, brechen wir den Connect ab.
    try {
        Invoke-PRTGRestMethod -Path '/health' -Method GET | Out-Null
    }
    catch {
        Clear-PRTGSession
        throw "Verbindung zu '$baseUri' konnte nicht verifiziert werden: $($_.Exception.Message)"
    }

    Write-Verbose "Erfolgreich verbunden mit $baseUri (Methode: $($tempSession.AuthMethod))"

    if ($PassThru) {
        [pscustomobject]@{
            BaseUri              = $baseUri
            AuthMethod           = $tempSession.AuthMethod
            SkipCertificateCheck = [bool]$SkipCertificateCheck
        }
    }
}
