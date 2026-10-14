<#
    .SYNOPSIS
    Creates one sensor of the same type on every device below a group or probe.

    .DESCRIPTION
    Walks the object tree below a starting object, collects every device it
    finds, and creates a single sensor type on each of them - a ping sensor on
    every device of a freshly migrated tree, for instance, so that something is
    being monitored before the real sensors exist.

    The script is idempotent: a device that already carries a sensor with that
    display name is reported and left alone, so it can be run again after
    fixing individual failures.

    Sensor creation goes through experimental API endpoints
    (/experimental/schemas, /experimental/sensors,
    POST /experimental/devices/{id}/sensor). Paessler may change those without
    notice. Try this against a test instance before pointing it at production.

    .PARAMETER ComputerName
    Host name or IP of the PRTG core server.

    .PARAMETER Port
    Port of the PRTG application server. Default 1616 - API v2 does not answer
    on 443, where the classic web server replies with a redirect to the login
    page or "401 Unsupported authorization scheme".

    .PARAMETER ParentGroupId
    Object id of the group to start from. Every device below it, at any depth,
    is included.

    .PARAMETER ParentProbeId
    Object id of a probe to start from instead of a group.

    .PARAMETER SensorDisplayName
    Display name of the sensor type to create, spelled exactly as PRTG shows it
    in the "add sensor" dialog. Default "Ping v2".

    Types are matched by display name rather than by kind identifier, because
    both exist in parallel: kind "ping" displays as "Ping", while
    "paessler.icmp.ping_sensor" displays as "Ping v2". The sensor created also
    carries this name.

    .PARAMETER ApiToken
    API key as a SecureString. Left out, the script asks for it. Pass it when
    the run has to work without a console, for instance from a scheduled task:
    ConvertTo-SecureString can read it from a protected file.

    .PARAMETER SkipCertificateCheck
    Skips TLS validation, for internal CAs or self-signed certificates.

    .PARAMETER RequestTimeoutMs
    Timeout per HTTP request in milliseconds. Default 60000. Collecting devices
    from a large tree and reading the sensor list of a busy device are the two
    calls that get slow first, so raise this before suspecting the API.

    .PARAMETER PageLimit
    Maximum number of objects requested per listing call. Default 3000. Only
    worth changing for a tree with more objects than that below one parent.

    .EXAMPLE
    .\Add-PRTGSensorToAllDevices.ps1 -ComputerName prtg.example.com -ParentGroupId 7003 -WhatIf

    Previews what would happen: how many devices were found, which of them
    already carry the sensor, and how many would be created. Creates nothing.

    .EXAMPLE
    .\Add-PRTGSensorToAllDevices.ps1 -ComputerName prtg.example.com -ParentGroupId 7003

    Creates a "Ping v2" sensor on every device below group 7003 that does not
    have one yet.

    .EXAMPLE
    .\Add-PRTGSensorToAllDevices.ps1 -ComputerName prtg.example.com -ParentProbeId 1 -SensorDisplayName 'SNMP Uptime' -SkipCertificateCheck

    The same for an SNMP uptime sensor below the local probe, on a server with
    a self-signed certificate.

    .NOTES
    Only sensor types that need no parameters of their own are suitable here.
    A ping or uptime sensor monitors the device and nothing else, so the same
    sensor makes sense on every device. An interface, disk or port sensor needs
    to be told what to watch, and creating it in bulk would produce sensors
    pointing at whatever PRTG picks first. Those belong in a discovery, or in
    one deliberate call per device.

    Author: Arne Brucker, netmon24 GmbH und Co. KG
#>
#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Group')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 1616,

    [Parameter(Mandatory, ParameterSetName = 'Group')]
    [string]$ParentGroupId,

    [Parameter(Mandatory, ParameterSetName = 'Probe')]
    [string]$ParentProbeId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SensorDisplayName = 'Ping v2',

    [Parameter()]
    [securestring]$ApiToken,

    [Parameter()]
    [switch]$SkipCertificateCheck,

    [Parameter()]
    [ValidateRange(1000, 600000)]
    [int]$RequestTimeoutMs = 60000,

    [Parameter()]
    [ValidateRange(1, 50000)]
    [int]$PageLimit = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootId = if ($PSCmdlet.ParameterSetName -eq 'Group') { $ParentGroupId } else { $ParentProbeId }

$token  = if ($ApiToken) { $ApiToken } else { Read-Host -AsSecureString -Prompt "PRTG API key for $ComputerName (port $Port)" }
$base   = "https://${ComputerName}:${Port}/api/v2"
$bearer = [System.Net.NetworkCredential]::new('', $token).Password
if (-not $bearer) { throw "No API key supplied." }

if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}

if ($SkipCertificateCheck) {
    # The callback has to be a compiled delegate. A method reference resolves to
    # a PSMethod in Windows PowerShell 5.1 and cannot be assigned; a ScriptBlock
    # is accepted but needs a runspace at call time, which the background thread
    # .NET calls it from does not have. Both failures surface as a closed
    # connection rather than as a certificate problem.
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

function Invoke-Raw {
    <#
        Minimal REST layer. HttpWebRequest rather than Invoke-RestMethod,
        because a failed call has to return its status code and body instead of
        throwing: an empty response body is normal for PRTG writes, and a 400
        from one device must not end the whole run.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET', 'POST')][string]$Method = 'GET',
        [hashtable]$Query,
        [object]$Body
    )

    $uri = $base + $Path
    if ($Query) {
        $pairs = foreach ($k in $Query.Keys) {
            "$([uri]::EscapeDataString($k))=$([uri]::EscapeDataString([string]$Query[$k]))"
        }
        $uri += '?' + ($pairs -join '&')
    }

    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method            = $Method
    $req.AllowAutoRedirect = $false
    $req.Timeout           = $RequestTimeoutMs
    $req.Accept            = 'application/json'
    $req.UserAgent         = 'PRTG-Sensor-Bulk'
    $req.Headers['Authorization'] = "Bearer $bearer"

    if ($null -ne $Body) {
        # UTF-8 bytes, not a string: a string body without a charset is encoded
        # as ISO-8859-1 by Windows PowerShell 5.1, which mangles umlauts.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 12 -Compress))
        $req.ContentType   = 'application/json; charset=utf-8'
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }

    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) {
            return [pscustomobject]@{ Status = $null; Content = $null; Raw = $_.Exception.Message }
        }
    }

    $status = [int]$resp.StatusCode
    $raw    = $null
    try {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $raw    = $reader.ReadToEnd()
        $reader.Close()
    }
    catch { }
    $resp.Close()

    $parsed = $null
    if ($raw) {
        $trimmed = $raw.TrimStart()
        if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
            try { $parsed = $raw | ConvertFrom-Json } catch { }
        }
    }

    [pscustomobject]@{ Status = $status; Content = $parsed; Raw = $raw }
}

$health = Invoke-Raw -Path '/health'
if ($health.Status -ne 200 -and $health.Status -ne 204) {
    throw "Connection failed (HTTP $($health.Status)). Port 1616? Token from the new interface? Certificate?"
}

Write-Host "Collecting groups below $rootId ..." -ForegroundColor Cyan
$containerIds = [System.Collections.Generic.List[string]]::new()
$queue        = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue($rootId)
while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $containerIds.Add($current)
    $sub = Invoke-Raw -Path '/experimental/groups' -Query @{ filter = ('parentid = "{0}"' -f $current); limit = $PageLimit }
    if ($sub.Status -eq 200 -and $sub.Content) {
        foreach ($g in @($sub.Content)) { if ($g.id) { $queue.Enqueue([string]$g.id) } }
    }
}
Write-Host "  $($containerIds.Count) container(s), including the starting object."

$devices = [System.Collections.Generic.List[object]]::new()
foreach ($containerId in $containerIds) {
    $found = Invoke-Raw -Path '/experimental/devices' -Query @{ filter = ('parentid = "{0}"' -f $containerId); limit = $PageLimit }
    if ($found.Status -eq 200 -and $found.Content) {
        foreach ($d in @($found.Content)) {
            if ($d.id) { $devices.Add([pscustomobject]@{ Id = [string]$d.id; Name = [string]$d.name }) }
        }
    }
}
Write-Host "  $($devices.Count) device(s) found." -ForegroundColor Cyan
if ($devices.Count -eq 0) {
    Write-Warning "No devices below $rootId - nothing to do."
    return
}

# Which types are creatable differs per device and per PRTG version, so ask a
# real device instead of guessing an identifier.
$schemas = Invoke-Raw -Path "/experimental/schemas/$($devices[0].Id)" -Query @{ limit = $PageLimit }
if ($schemas.Status -ne 200) {
    throw "Could not read sensor types from device $($devices[0].Id) (HTTP $($schemas.Status)): $($schemas.Raw)"
}
$kind = @($schemas.Content) |
    Where-Object { $_.creatable -and "$($_.name)".Trim() -eq $SensorDisplayName } |
    Select-Object -First 1
if (-not $kind) {
    $available = (@($schemas.Content) | Where-Object creatable | ForEach-Object { $_.name } | Sort-Object -Unique) -join ', '
    throw "No creatable sensor type is displayed as '$SensorDisplayName'. Available on device $($devices[0].Id): $available"
}
Write-Host "  '$SensorDisplayName' resolves to kind '$($kind.kind)'" -ForegroundColor Cyan
Write-Host ""

$created = 0
$exists  = 0
$failed  = 0
$pending = 0

foreach ($device in $devices) {
    $have = Invoke-Raw -Path '/experimental/sensors' -Query @{ filter = ('parentid = "{0}"' -f $device.Id); limit = $PageLimit }
    if ($have.Status -ne 200) {
        Write-Warning "  $($device.Name): could not read existing sensors (HTTP $($have.Status)) - skipped rather than risking a duplicate."
        $failed++
        continue
    }
    if (@($have.Content | ForEach-Object { "$($_.name)" }) -contains $SensorDisplayName) {
        Write-Host "  [exists]  $($device.Name)"
        $exists++
        continue
    }

    if (-not $PSCmdlet.ShouldProcess("$($device.Name) (id $($device.Id))", "Create sensor '$SensorDisplayName'")) {
        # Reached under -WhatIf, and when a confirmation prompt is declined.
        # Counted either way, so the summary describes the run instead of
        # reporting three zeros for a preview that found plenty to do.
        $pending++
        continue
    }

    $post = @{
        Path   = "/experimental/devices/$($device.Id)/sensor"
        Method = 'POST'
        Query  = @{ kindid = $kind.kind }
        Body   = @{ basic = @{ name = $SensorDisplayName } }
    }
    $result = Invoke-Raw @post

    if ($result.Status -eq 200 -or $result.Status -eq 201) {
        Write-Host "  [created] $($device.Name)" -ForegroundColor Green
        $created++
    }
    else {
        Write-Warning "  $($device.Name): HTTP $($result.Status) - $($result.Raw)"
        $failed++
    }
}

Write-Host ""
if ($WhatIfPreference) {
    Write-Host "Preview: $pending sensor(s) would be created, $exists already present, $($devices.Count) device(s) checked." -ForegroundColor Yellow
    if ($failed -gt 0) {
        Write-Host "         $failed device(s) could not be read and would be skipped." -ForegroundColor Yellow
    }
    Write-Host "Run the same command without -WhatIf to create them." -ForegroundColor Yellow
}
else {
    Write-Host "created $created   already present $exists   failed $failed" -ForegroundColor Yellow
    if ($pending -gt 0) {
        Write-Host "$pending device(s) left untouched because the confirmation was declined." -ForegroundColor Yellow
    }
}
