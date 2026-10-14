<#
    .SYNOPSIS
    Reports which fields the API v2 expects when creating a sensor type. Reads
    only, creates nothing.

    .DESCRIPTION
    Answers the question that stops every bulk sensor creation: a sensor type
    such as "SNMP Traffic" or "Disk Free" needs to be told what to watch, and
    the API v2 documentation does not say which fields carry that information.

    The script reads the creatable sensor types of one reference device, fetches
    the POST schema for each display name you ask about, and writes every raw
    response to disk. The JSON files are the actual deliverable - they show the
    field names, which of them are mandatory, and which values the server
    accepts, so a sensor type can be scripted without guessing.

    It is deliberately read-only: every request is a GET, so it is safe to point
    at production. Nothing is created, changed or deleted.

    The schema endpoints are experimental (/experimental/schemas/{deviceId},
    /experimental/schemas/{deviceId}/post). Paessler may change them without
    notice, which is also why the script reports the top-level keys it actually
    found instead of assuming a documented shape.

    .PARAMETER ComputerName
    Host name or IP of the PRTG core server.

    .PARAMETER Port
    Port of the PRTG application server. Default 1616 - API v2 does not answer
    on 443, where the classic web server replies with a redirect to the login
    page or "401 Unsupported authorization scheme".

    .PARAMETER DeviceId
    Object id of the reference device. Any existing device works, but the
    creatable types are reported per device, so pick one that resembles the
    devices you intend to create sensors on: a switch to investigate interface
    sensors, a server for disk and service sensors.

    .PARAMETER SensorDisplayName
    Display names to investigate, spelled as PRTG shows them in the "add
    sensor" dialog. The default is a spread across the interesting cases:
    types that need no parameters, and types that clearly need extra ones.

    Names are matched by display name rather than by kind identifier, because
    both exist in parallel: kind "ping" displays as "Ping", while
    "paessler.icmp.ping_sensor" displays as "Ping v2".

    .PARAMETER OutDir
    Folder for the raw responses. Created if missing. Contains kinds.json (all
    reported types), one post-<kind>.json per type, and summary.csv.

    .PARAMETER ApiToken
    API key as a SecureString. Left out, the script asks for it. Pass it when
    the run has to work without a console, for instance from a scheduled task:
    ConvertTo-SecureString can read it from a protected file.

    .PARAMETER SkipCertificateCheck
    Skips TLS validation, for internal CAs or self-signed certificates.

    .PARAMETER RequestTimeoutMs
    Timeout per HTTP request in milliseconds. Default 60000. Reading the type
    list of a device on a busy server is the call that gets slow first, so
    raise this before suspecting the API.

    .PARAMETER PageLimit
    Maximum number of types requested in one listing call. Default 3000, which
    covers every device seen so far - PRTG reports a few hundred types even on
    a plain device.

    .EXAMPLE
    .\Get-PRTGSensorSchemas.ps1 -ComputerName prtg.example.com -DeviceId 2001

    Investigates the default set of display names on device 2001 and writes the
    raw responses to .\prtg-schema-probe.

    .EXAMPLE
    .\Get-PRTGSensorSchemas.ps1 -ComputerName prtg.example.com -DeviceId 2001 -SensorDisplayName 'SNMP Traffic','Disk Free' -SkipCertificateCheck

    Only the two types that need parameters, on a server with a self-signed
    certificate.

    .EXAMPLE
    .\Get-PRTGSensorSchemas.ps1 -ComputerName prtg.example.com -DeviceId 2001 -ApiToken (ConvertTo-SecureString -String (Get-Content C:\secure\prtg.key) -AsPlainText -Force)

    Unattended run without a console prompt.

    .NOTES
    Read-only. Every request is a GET, nothing is written to PRTG.

    Deliberately independent of the PRTG.PowerShell module: it talks to the API
    with HttpWebRequest so that it also works where the module is not installed
    yet, and so that it shows the unmodified server response rather than
    something the module has already interpreted.

    Author: Arne Brucker, netmon24 GmbH und Co. KG
    License: MIT
#>
#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ComputerName,
    [Parameter()][ValidateRange(1, 65535)][int]$Port = 1616,

    [Parameter(Mandatory)][string]$DeviceId,

    [Parameter()][string[]]$SensorDisplayName = @(
        'Ping', 'Ping v2', 'HTTP', 'DNS', 'CPU Load', 'Memory',
        'SNMP Traffic', 'Disk Free', 'Port'
    ),

    [Parameter()][string]$OutDir = '.\prtg-schema-probe',
    [Parameter()][System.Security.SecureString]$ApiToken,
    [Parameter()][switch]$SkipCertificateCheck,
    [Parameter()][ValidateRange(1000, 600000)][int]$RequestTimeoutMs = 60000,
    [Parameter()][ValidateRange(1, 50000)][int]$PageLimit = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$token = $ApiToken
if (-not $token) {
    $token = Read-Host -AsSecureString -Prompt "PRTG API key for $ComputerName (port $Port)"
}

$base   = "https://${ComputerName}:${Port}/api/v2"
$bearer = [System.Net.NetworkCredential]::new('', $token).Password

if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}
if ($SkipCertificateCheck) {
    # A ScriptBlock is rejected here at runtime, so the callback has to be a
    # compiled delegate.
    if (-not ('PRTGRaw.CertBypass' -as [type])) {
        Add-Type -Namespace PRTGRaw -Name CertBypass -MemberDefinition @'
            public static bool Validate(object sender, System.Security.Cryptography.X509Certificates.X509Certificate certificate, System.Security.Cryptography.X509Certificates.X509Chain chain, System.Net.Security.SslPolicyErrors sslPolicyErrors) { return true; }
'@
    }
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback =
        [System.Delegate]::CreateDelegate(
            [System.Net.Security.RemoteCertificateValidationCallback],
            [PRTGRaw.CertBypass], 'Validate')
}

function Get-Raw {
    param(
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query
    )
    $uri = $base + $Path
    if ($Query) {
        $pairs = foreach ($k in $Query.Keys) { "$([uri]::EscapeDataString($k))=$([uri]::EscapeDataString([string]$Query[$k]))" }
        $uri += '?' + ($pairs -join '&')
    }
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method            = 'GET'
    $req.AllowAutoRedirect = $false
    $req.Timeout           = $RequestTimeoutMs
    $req.Accept            = 'application/json'
    $req.UserAgent         = 'PRTG-Schema-Probe'
    $req.Headers['Authorization'] = "Bearer $bearer"
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { return [pscustomobject]@{ Status = $null; Content = $null; Raw = $_.Exception.Message } }
    }
    $status = [int]$resp.StatusCode
    $raw = $null
    try { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8); $raw = $sr.ReadToEnd(); $sr.Close() } catch { }
    $resp.Close()
    $parsed = $null
    if ($raw) { $t = $raw.TrimStart(); if ($t.StartsWith('{') -or $t.StartsWith('[')) { try { $parsed = $raw | ConvertFrom-Json } catch { } } }
    [pscustomobject]@{ Status = $status; Content = $parsed; Raw = $raw }
}

$h = Get-Raw -Path '/health'
if ($h.Status -ne 200 -and $h.Status -ne 204) {
    throw "Connection failed (HTTP $($h.Status)). Port $Port reachable? API key from the new interface? Certificate accepted?"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Write-Host "Writing raw responses to $OutDir" -ForegroundColor DarkGray

# --- 1. Creatable types of the reference device -----------------------------
Write-Host ""
Write-Host "Reading creatable sensor types for device $DeviceId ..." -ForegroundColor Cyan
$kindsResp = Get-Raw -Path "/experimental/schemas/$DeviceId" -Query @{ limit = $PageLimit }
if ($kindsResp.Status -ne 200) { throw "HTTP $($kindsResp.Status): $($kindsResp.Raw)" }
$kindsResp.Raw | Set-Content (Join-Path $OutDir 'kinds.json') -Encoding UTF8

$all       = @($kindsResp.Content)
$creatable = @($all | Where-Object creatable)
Write-Host "  $($all.Count) types reported, $($creatable.Count) creatable."

# --- 2. POST schema per requested display name ------------------------------
$report = [System.Collections.Generic.List[object]]::new()

foreach ($wanted in $SensorDisplayName) {
    $kind = $creatable | Where-Object { "$($_.name)".Trim() -eq $wanted } | Select-Object -First 1

    if (-not $kind) {
        Write-Host ("  {0,-16} not creatable on this device" -f $wanted) -ForegroundColor DarkYellow
        $report.Add([pscustomobject]@{ DisplayName = $wanted; Kind = $null; Status = 'not creatable'; Fields = $null })
        continue
    }

    $schema = Get-Raw -Path "/experimental/schemas/$DeviceId/post" -Query @{ kindid = $kind.kind }

    $safe = ($kind.kind -replace '[^A-Za-z0-9._-]', '_')
    if ($schema.Raw) { $schema.Raw | Set-Content (Join-Path $OutDir "post-$safe.json") -Encoding UTF8 }

    if ($schema.Status -ne 200) {
        Write-Host ("  {0,-16} kind {1}  -> HTTP {2}" -f $wanted, $kind.kind, $schema.Status) -ForegroundColor DarkYellow
        $report.Add([pscustomobject]@{ DisplayName = $wanted; Kind = $kind.kind; Status = "HTTP $($schema.Status)"; Fields = $null })
        continue
    }

    # The schema shape is not documented, so report what is actually there
    # instead of assuming property names.
    $topKeys = @()
    if ($schema.Content) { $topKeys = @($schema.Content.PSObject.Properties.Name) }

    Write-Host ("  {0,-16} kind {1}" -f $wanted, $kind.kind) -ForegroundColor Green
    Write-Host ("       top-level keys: {0}" -f ($topKeys -join ', '))
    Write-Host ("       bytes: {0}" -f $schema.Raw.Length)

    $report.Add([pscustomobject]@{
        DisplayName = $wanted
        Kind        = $kind.kind
        Status      = 'ok'
        Fields      = ($topKeys -join ', ')
    })
}

# --- 3. Summary -------------------------------------------------------------
Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Yellow
$report | Format-Table DisplayName, Kind, Status -AutoSize

$report | Export-Csv -Path (Join-Path $OutDir 'summary.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host "All creatable display names on this device:" -ForegroundColor Cyan
($creatable | ForEach-Object { $_.name } | Sort-Object -Unique) -join ' | '
Write-Host ""
Write-Host "Raw JSON per type is in $OutDir - post-*.json holds the field list for each type." -ForegroundColor DarkGray
