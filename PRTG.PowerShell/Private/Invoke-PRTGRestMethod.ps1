function Invoke-PRTGRestMethod {
    <#
        .SYNOPSIS
        Interne Funktion. Führt einen HTTP-Aufruf gegen die PRTG API v2 aus.

        .DESCRIPTION
        Diese Funktion ist das Rückgrat des gesamten Moduls. Alle Public-Cmdlets
        (Get-, New-, Set-, Remove-, Pause-, Resume-, ... ) rufen letztlich diese
        Funktion auf. Sie kümmert sich um:
          - Aufbau der vollständigen URL aus BaseUri + Pfad + Query-Parametern
          - Authentifizierung (Bearer Token aus der aktiven Session)
          - Optionales Überspringen der Zertifikatsprüfung (-SkipCertificateCheck der Session)
          - Einheitliche Fehlerbehandlung inkl. lesbarer Fehlermeldungen aus dem
            PRTG-Problem-JSON ("code", "message", "request_id")
          - JSON (de-)Serialisierung

        .PARAMETER Path
        Der API-Pfad relativ zur Basis-URL, z.B. '/devices/2322' oder '/experimental/devices'.
        Der Pfad darf KEIN führendes '/api/v2' enthalten, das wird automatisch ergänzt.

        .PARAMETER Method
        HTTP-Methode (GET, POST, PATCH, DELETE). Standard: GET.

        .PARAMETER QueryParameter
        Hashtable mit Query-String-Parametern, z.B. @{ limit = 500; filter = 'active=true' }.
        $null- oder leere Werte werden automatisch herausgefiltert.

        .PARAMETER Body
        Optionales Objekt (Hashtable/PSObject), das als JSON-Body gesendet wird (POST/PATCH).

        .NOTES
        Nicht für direkten Endanwender-Gebrauch gedacht. Wird ausschließlich von den
        Public-Cmdlets dieses Moduls verwendet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [hashtable]$QueryParameter,

        [Parameter()]
        [object]$Body
    )

    $session = Get-PRTGSession

    # --- URL zusammensetzen -------------------------------------------------
    $uri = $session.BaseUri.TrimEnd('/') + '/api/v2' + $Path

    if ($QueryParameter -and $QueryParameter.Count -gt 0) {
        $pairs = foreach ($key in $QueryParameter.Keys) {
            $value = $QueryParameter[$key]
            if ($null -eq $value -or $value -eq '') { continue }

            # Arrays werden gemäß OpenAPI-Spec als CSV (comma separated values) übergeben,
            # z.B. include=all_sections,inheritance
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = ($value -join ',')
            }
            "$([uri]::EscapeDataString($key))=$([uri]::EscapeDataString([string]$value))"
        }
        if ($pairs) {
            $uri += '?' + ($pairs -join '&')
        }
    }

    # --- Request-Parameter für Invoke-RestMethod zusammensetzen -------------
    $irmParams = @{
        Uri         = $uri
        Method      = $Method
        Headers     = @{
            'Authorization' = "Bearer $($session.ApiToken)"
            'Accept'        = 'application/json'
        }
        ErrorAction = 'Stop'
    }

    if ($Body) {
        # WICHTIG: Body als UTF-8-BYTES uebergeben, nicht als String.
        # Windows PowerShell 5.1 kodiert einen String-Body ohne charset-Angabe
        # als ISO-8859-1. Umlaute werden dadurch zerstoert - beobachtet am
        # 2026-09-25: Geraetenamen mit "Domaene" landeten als "Dom?ne" in PRTG.
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $irmParams['Body']        = [System.Text.Encoding]::UTF8.GetBytes($json)
        $irmParams['ContentType'] = 'application/json; charset=utf-8'
    }

    # Zertifikatsprüfung überspringen, falls beim Connect angefordert.
    # PowerShell 7+ unterstützt -SkipCertificateCheck direkt; für Windows PowerShell 5.1
    # (Standard auf Windows Server 2016) wird ein Callback-Workaround verwendet.
    $restoreCallback = $false
    if ($session.SkipCertificateCheck) {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $irmParams['SkipCertificateCheck'] = $true
        }
        else {
            # Windows PowerShell 5.1 Workaround: Invoke-RestMethod kennt dort kein
            # -SkipCertificateCheck. Stattdessen wird der prozessweite Zertifikats-
            # Validierungs-Callback temporär überschrieben und im finally-Block
            # wieder zurückgesetzt.
            #
            # Die Zuweisung ist heikler als sie aussieht - zwei Varianten scheitern:
            #
            #   1) [PRTG.CertificateValidationBypass]::Validate  (Methodenverweis)
            #      liefert in PS 5.1 ein PSMethod-Objekt. Fehler beim Zuweisen:
            #        Cannot convert ... "System.Management.Automation.PSMethod"
            #        to type "System.Net.Security.RemoteCertificateValidationCallback"
            #      Methodengruppen-Konvertierung gibt es erst ab PowerShell 6.
            #
            #   2) Ein ScriptBlock ({ param(...) $true }) wird zwar angenommen,
            #      PowerShell erzeugt daraus aber eine Lambda, die zur Laufzeit
            #      einen Runspace braucht. .NET ruft den Callback jedoch aus einem
            #      Hintergrund-Thread ohne Runspace auf. Fehler zur Laufzeit:
            #        There is no Runspace available to run scripts in this thread.
            #      Nach außen erscheint das als:
            #        The underlying connection was closed: An unexpected error
            #        occurred on a send.
            #
            # Tragfähig ist nur ein echter, kompilierter Delegat auf die C#-Methode.
            # System.Delegate::CreateDelegate erzeugt genau den - ohne Runspace-Bezug.
            if (-not ('PRTG.CertificateValidationBypass' -as [type])) {
                Add-Type -Namespace PRTG -Name CertificateValidationBypass -MemberDefinition @'
                    public static bool Validate(object sender, System.Security.Cryptography.X509Certificates.X509Certificate certificate, System.Security.Cryptography.X509Certificates.X509Chain chain, System.Net.Security.SslPolicyErrors sslPolicyErrors) { return true; }
'@
            }
            $previousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [System.Delegate]::CreateDelegate(
                [System.Net.Security.RemoteCertificateValidationCallback],
                [PRTG.CertificateValidationBypass],
                'Validate')
            $restoreCallback = $true

            # PS 5.1 verhandelt je nach Windows-Version noch TLS 1.0. PRTG erwartet
            # mindestens TLS 1.2. Vorhandene Protokolle bleiben erhalten (-bor).
            if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            }
        }
    }

    try {
        try {
            return Invoke-RestMethod @irmParams
        }
        finally {
            if ($restoreCallback) {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCallback
            }
        }
    }
    catch {
        # Versuche, das strukturierte PRTG-Problem-JSON aus der Fehlerantwort zu lesen,
        # damit der Anwender eine sprechende Fehlermeldung statt eines rohen HTTP-Fehlers sieht.
        $errorRecord    = $_
        $statusCode     = $null
        $prtgErrorBody  = $null

        if ($errorRecord.Exception.Response) {
            try {
                $statusCode = [int]$errorRecord.Exception.Response.StatusCode
            }
            catch { }

            try {
                # .NET Framework / Windows PowerShell 5.1
                $stream = $errorRecord.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $raw    = $reader.ReadToEnd()
                if ($raw) { $prtgErrorBody = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue }
            }
            catch { }
        }
        elseif ($errorRecord.ErrorDetails -and $errorRecord.ErrorDetails.Message) {
            # PowerShell 7 (Invoke-RestMethod liefert hier den Body direkt)
            try {
                $prtgErrorBody = $errorRecord.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch { }
        }

        if ($prtgErrorBody -and $prtgErrorBody.message) {
            $detail = "PRTG-API-Fehler [$($prtgErrorBody.code)]: $($prtgErrorBody.message)"
            if ($prtgErrorBody.request_id) {
                $detail += " (request_id: $($prtgErrorBody.request_id))"
            }
            throw $detail
        }
        else {
            throw "PRTG-API-Aufruf fehlgeschlagen ($Method $uri): $($errorRecord.Exception.Message)"
        }
    }
}
