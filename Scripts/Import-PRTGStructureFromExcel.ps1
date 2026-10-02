<#
    .SYNOPSIS
    Recreates a PRTG tree - groups, devices and optionally sensors - in a
    target PRTG system from an Excel sensor export.

    .DESCRIPTION
    Built for migrations: you export the sensor list from an existing PRTG
    installation (or assemble the same columns by hand) and this script
    rebuilds that structure in a new system.

    Three steps, in order:

      1. GROUPS from column "group", created one level below a target parent.
         The parent is either a probe (-ParentProbeId / -ParentProbeName) or
         an existing group (-ParentGroupId), for instance a collection group
         prepared beforehand. One level only - no nested sub-groups.

      2. DEVICES from columns "device" and "host", one per group. The display
         name follows the convention "<device> (IP: <host>)" while the value
         from "host" becomes the monitored address. New devices also get
         PRTG's classic "discoverytype" setting so the server starts its own
         auto-discovery; -SkipSensorDiscovery turns that off.

      3. SENSORS from column "sensor" - only with -CreateSensors, and only
         those listed in the sheet. Which ones are considered is narrowed by
         -SensorKindFilter (default: ping).

    The script is idempotent. Existing groups, devices and sensors are matched
    by name below their respective parent and skipped rather than duplicated,
    so running it again after fixing individual errors is safe. -WhatIf is
    supported and reaches the API through the cmdlets used.

    .NOTES
    STABILITY: steps 1 and 2 use this module's cmdlets, which target stable
    API v2 endpoints. Step 3 does not - creating sensors requires
    /experimental/schemas, /experimental/sensors and
    POST /experimental/devices/{id}/sensor. Paessler may change experimental
    endpoints without notice, so treat -CreateSensors as the part most likely
    to need maintenance, and try it on a test instance first.

    REQUIREMENTS: the ImportExcel module (Install-Module ImportExcel), which
    reads .xlsx files without Excel being installed.

    An example workbook ships with this repository under
    examples/PRTG-Export-Demo.xlsx.

    .PARAMETER ExcelPath
    Path to the .xlsx file holding the export.

    .PARAMETER WorksheetName
    Worksheet with the sensor rows. Default "Sensoren", the name produced by
    a German PRTG export.

    .PARAMETER ParentProbeId
    Object id of the target probe the groups are created under. Find it with
    Get-PRTGProbe.

    .PARAMETER ParentProbeName
    Name of the target probe instead of its id; resolved via Get-PRTGProbe.
    Without either parameter the probe name from the sheet's first row
    (column "probe") is used.

    .PARAMETER ParentGroupId
    Object id of an existing group to create below, instead of a probe. Find
    it with Get-PRTGGroup.

    .PARAMETER ComputerName
    Target PRTG core server.

    .PARAMETER Port
    Port of the PRTG application server. Default 1616 - API v2 does not answer
    on 443, where the classic web server replies with a 302 to the login page
    or "401 Unsupported authorization scheme".

    .PARAMETER SkipCertificateCheck
    Skips TLS validation, for internal CAs or self-signed certificates.

    .PARAMETER SensorDiscoveryMode
    Value for PRTG's "discoverytype" device setting: Manual (0) performs no
    auto-discovery, Standard (1) uses the standard sensor types, Detailed (2)
    uses all known types and comes closest to the variety found in a typical
    source export.

    .PARAMETER SkipSensorDiscovery
    Does not set "discoverytype" at all. Devices are created with PRTG's own
    default, so sensors have to be discovered manually afterwards.

    .PARAMETER CreateSensors
    Also creates the sensors listed in the sheet. See the stability note above.

    .PARAMETER SensorKindFilter
    Search terms preselecting which sensor names from the sheet are considered.
    The actual PRTG kind is resolved against the target system at runtime
    because the identifiers differ between PRTG versions. Default: ping only.

    .PARAMETER ExportCsv
    Writes a log of every group, device and sensor touched to this path.

    .EXAMPLE
    .\Import-PRTGStructureFromExcel.ps1 -ExcelPath '.\examples\PRTG-Export-Demo.xlsx' `
        -ComputerName 'prtg.example.com' -ParentProbeName 'Demo Probe' -WhatIf

    Preview without changes. Always the recommended first step.

    .EXAMPLE
    .\Import-PRTGStructureFromExcel.ps1 -ExcelPath 'C:\Temp\export.xlsx' `
        -ComputerName 'prtg.example.com' -ParentProbeId 1

    Groups and devices below the local probe.

    .EXAMPLE
    .\Import-PRTGStructureFromExcel.ps1 -ExcelPath 'C:\Temp\export.xlsx' `
        -ComputerName 'prtg.example.com' -ParentGroupId 7003

    Imports into an existing collection group - the common case when a
    customer-specific container has been prepared.

    .EXAMPLE
    .\Import-PRTGStructureFromExcel.ps1 -ExcelPath 'C:\Temp\export.xlsx' `
        -ComputerName 'prtg.example.com' -ParentProbeId 1 `
        -SkipSensorDiscovery -CreateSensors -SensorKindFilter ping, http

    Creates exactly the ping and HTTP sensors from the sheet and nothing else:
    auto-discovery stays off, so no sensors appear that the sheet does not ask
    for.

    .EXAMPLE
    .\Import-PRTGStructureFromExcel.ps1 -ExcelPath 'C:\Temp\export.xlsx' `
        -ComputerName 'prtg.example.com' -ParentProbeId 1 -ExportCsv .\import-log.csv

    Logs the result as semicolon-separated CSV.
#>
#requires -Modules PRTG.PowerShell
#requires -Modules ImportExcel
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ProbeId')]
param(
    [Parameter(Mandatory)]
    [string]$ExcelPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorksheetName = 'Sensoren',

    [Parameter(Mandatory, ParameterSetName = 'ProbeId')]
    [string]$ParentProbeId,

    [Parameter(ParameterSetName = 'ProbeName')]
    [string]$ParentProbeName,

    [Parameter(Mandatory, ParameterSetName = 'GroupId')]
    [string]$ParentGroupId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 1616,

    [Parameter()]
    [switch]$SkipCertificateCheck,

    [Parameter()]
    [ValidateSet('Manual', 'Standard', 'Detailed')]
    [string]$SensorDiscoveryMode = 'Detailed',

    [Parameter()]
    [switch]$SkipSensorDiscovery,

    [Parameter()]
    [switch]$CreateSensors,

    [Parameter()]
    [string[]]$SensorKindFilter = @('ping'),

    [Parameter()]
    [string]$ExportCsv
)

# ---------------------------------------------------------------------
# Lessons that cost time to learn - please do not "simplify" them away
# ---------------------------------------------------------------------
#  1) PORT: API v2 lives on the application server (1616), not on 443. On the
#     classic port every /api/v2 path answers 302 to the login page, and a
#     Bearer header yields "401 Unsupported authorization scheme" - error
#     messages that misleadingly suggest a TLS problem.
#  2) CERTIFICATE: the validation bypass MUST be a compiled delegate created
#     with [System.Delegate]::CreateDelegate. A method reference resolves to a
#     PSMethod under PowerShell 5.1 and fails to convert; a ScriptBlock fails
#     later with "There is no Runspace available".
#  3) FILTERS: text values must be wrapped in double quotes - parentid = "7003".
#     Without them the API answers 400 Bad Request. Numbers, booleans and enums
#     take no quotes. Conditions combine with "and"/"or", never with ";".
#     Do not filter on names containing ( ) [ ] or & - parentheses group in the
#     filter syntax, so such names silently fail to match.
#  4) HTTP: HttpWebRequest rather than Invoke-WebRequest, because redirect
#     handling needs to be switched off explicitly under PowerShell 5.1.
#  5) ASYNCHRONY: objects are not queryable the instant their POST returns.
#     Creation succeeds, an immediate lookup finds nothing, and seconds later
#     everything is there. Retry instead of giving up on the first miss.
#  6) SENSOR TYPES: map via the kind's DISPLAY NAME, not its identifier. Both
#     exist side by side - kind 'ping' displays as 'Ping' while
#     'paessler.icmp.ping_sensor' displays as 'Ping v2'. Searching for the
#     term "ping" hits the wrong one.
# ---------------------------------------------------------------------

$ScriptVersion = '1.0.0'
Write-Host "Import-PRTGStructureFromExcel.ps1  version $ScriptVersion" -ForegroundColor DarkGray

# ---------------------------------------------------------------------
# Embedded REST layer for the PRTG API v2
# ---------------------------------------------------------------------
# Used only with -CreateSensors. The module has no sensor cmdlets, and its
# Invoke-PRTGRestMethod is private and returns the response body only - too
# little for status codes and Location headers.
#
# Deliberately embedded rather than placed in a lib folder: these scripts get
# copied to the target machine by hand, and a forgotten second file costs a
# run every time. One file, one copy.
# ---------------------------------------------------------------------
$script:PRTGRawSession = $null

function Connect-PRTGRawSession {
    <#
        .SYNOPSIS
        Builds the raw connection context and verifies it against /health.

        .PARAMETER ApiToken
        API key as a SecureString. It must come from the new interface
        (https://<host>:1616, Account Settings, My Account, API Keys). A key
        from the classic interface is rejected with "400 invalid session token
        or API token format".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter()][int]$Port = 1616,
        [Parameter(Mandatory)][securestring]$ApiToken,
        [Parameter()][switch]$SkipCertificateCheck
    )

    # Enable TLS 1.2 additively - depending on the Windows version PS 5.1 would
    # otherwise still offer TLS 1.0, which PRTG rejects.
    if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    }

    if ($SkipCertificateCheck) {
        if (-not ('PRTGRaw.CertBypass' -as [type])) {
            Add-Type -Namespace PRTGRaw -Name CertBypass -MemberDefinition @'
                public static bool Validate(object sender, System.Security.Cryptography.X509Certificates.X509Certificate certificate, System.Security.Cryptography.X509Certificates.X509Chain chain, System.Net.Security.SslPolicyErrors sslPolicyErrors) { return true; }
'@
        }
        # See lesson 2 at the top of this file.
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback =
            [System.Delegate]::CreateDelegate(
                [System.Net.Security.RemoteCertificateValidationCallback],
                [PRTGRaw.CertBypass], 'Validate')
    }

    $script:PRTGRawSession = [pscustomobject]@{
        BaseUri = "https://${ComputerName}:${Port}/api/v2"
        Token   = [System.Net.NetworkCredential]::new('', $ApiToken).Password
    }

    $r = Invoke-PRTGRawRest -Path '/health' -Method GET
    if ($r.StatusCode -ne 204 -and $r.StatusCode -ne 200) {
        $script:PRTGRawSession = $null
        throw @"
Connection to https://${ComputerName}:${Port} failed (HTTP $($r.StatusCode)).
Response: $($r.Raw)
Check:
  - Port: API v2 runs on 1616, not on 443
  - Token: must come from the new interface (https://${ComputerName}:1616)
  - Certificate: use -SkipCertificateCheck with an internal CA
"@
    }
    Write-Verbose "Connected to $($script:PRTGRawSession.BaseUri)"
}

function Invoke-PRTGRawRest {
    <#
        .SYNOPSIS
        Calls the PRTG API v2 and returns the full response.

        .DESCRIPTION
        Unlike the module cmdlet this returns status code, headers, parsed
        content and raw text, which the sensor endpoints need.

        .OUTPUTS
        PSCustomObject with StatusCode, Headers, Content, Raw, Error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method = 'GET',
        [Parameter()][hashtable]$QueryParameter,
        [Parameter()][object]$Body
    )

    if (-not $script:PRTGRawSession) {
        throw "No active raw connection. Run Connect-PRTGRawSession first."
    }

    $uri = $script:PRTGRawSession.BaseUri + $Path
    if ($QueryParameter -and $QueryParameter.Count -gt 0) {
        $pairs = foreach ($k in $QueryParameter.Keys) {
            $v = $QueryParameter[$k]
            if ($null -eq $v -or $v -eq '') { continue }
            if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { $v = ($v -join ',') }
            "$([uri]::EscapeDataString($k))=$([uri]::EscapeDataString([string]$v))"
        }
        if ($pairs) { $uri += '?' + ($pairs -join '&') }
    }

    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method            = $Method
    $req.AllowAutoRedirect = $false   # see lesson 4
    $req.Timeout           = 60000
    $req.Accept            = 'application/json'
    $req.UserAgent         = 'PRTG-Excel-Import'
    $req.Headers['Authorization'] = "Bearer $($script:PRTGRawSession.Token)"

    if ($null -ne $Body) {
        $json  = $Body | ConvertTo-Json -Depth 12 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req.ContentType   = 'application/json'
        $req.ContentLength = $bytes.Length
        $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
    }

    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) {
            return [pscustomobject]@{ StatusCode = $null; Headers = $null; Content = $null; Raw = $null; Error = $_.Exception.Message }
        }
    }
    catch {
        return [pscustomobject]@{ StatusCode = $null; Headers = $null; Content = $null; Raw = $null; Error = $_.Exception.Message }
    }

    $status = [int]$resp.StatusCode
    $hdrs   = @{}
    foreach ($h in $resp.Headers.AllKeys) { $hdrs[$h] = $resp.Headers[$h] }

    $raw = $null
    try {
        $sr  = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $raw = $sr.ReadToEnd(); $sr.Close()
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

    [pscustomobject]@{
        StatusCode = $status
        Headers    = $hdrs
        Content    = $parsed
        Raw        = $raw
        Error      = $null
    }
}

# ---------------------------------------------------------------------
# Input normalisation
# ---------------------------------------------------------------------
# Called without parameters, PowerShell prompts for the mandatory ones and
# reads the line RAW - it strips neither surrounding quotes nor leading or
# trailing spaces. Anyone pasting a path from the examples above (where the
# quotes belong, because the command line needs them) ends up with a value
# including those quotes, and Test-Path fails. Normalise instead of validating
# strictly on the parameter.
function Get-NormalizedPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    return $Path.Trim().Trim('"').Trim("'").Trim()
}

$ExcelPath = Get-NormalizedPath -Path $ExcelPath

if (-not (Test-Path -LiteralPath $ExcelPath -PathType Leaf)) {
    throw @"
Excel file not found: '$ExcelPath'
Either the path is wrong, or a folder was given instead of a file.
At the interactive prompt enter the path WITHOUT quotes; on the command line
use them: -ExcelPath 'C:\Temp\PRTG Export.xlsx'
"@
}

Import-Module PRTG.PowerShell -ErrorAction Stop
Import-Module ImportExcel -ErrorAction Stop

# Classic PRTG values for the "discoverytype" device setting. The mapping comes
# from the classic interface. Whether API v2 expects the field at exactly
# "basic.discoverytype" is NOT verified - the module covers no discovery write
# endpoints. The device creation below therefore catches a failure on this
# field and retries without it rather than aborting the whole import.
$discoveryTypeMap = @{ Manual = 0; Standard = 1; Detailed = 2 }

# ---------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------
# The token is always requested when sensors are to be created: the module
# keeps its session private, while the sensor endpoints go through the embedded
# REST layer. One token, two connections.
$apiToken = $null
$alreadyConnected = Test-PRTGServerHealth -WarningAction SilentlyContinue

if (-not $alreadyConnected -or $CreateSensors) {
    $apiToken = Read-Host -AsSecureString -Prompt "PRTG API key for $ComputerName (port $Port)"
}

if (-not $alreadyConnected) {
    $connectParams = @{
        ComputerName         = $ComputerName
        Port                 = $Port
        ApiToken             = $apiToken
        SkipCertificateCheck = $SkipCertificateCheck
    }
    Connect-PRTGServer @connectParams
}

if ($CreateSensors) {
    Connect-PRTGRawSession -ComputerName $ComputerName -Port $Port -ApiToken $apiToken -SkipCertificateCheck:$SkipCertificateCheck
}

# ---------------------------------------------------------------------
# Read the worksheet
# ---------------------------------------------------------------------
Write-Host "Reading '$ExcelPath' (worksheet '$WorksheetName') ..." -ForegroundColor Cyan
$rows = Import-Excel -Path $ExcelPath -WorksheetName $WorksheetName

if (-not $rows -or $rows.Count -eq 0) {
    throw "Worksheet '$WorksheetName' in '$ExcelPath' contains no rows."
}

foreach ($required in 'probe', 'group', 'device', 'host') {
    if (-not ($rows[0].PSObject.Properties.Name -contains $required)) {
        throw "Required column '$required' is missing from worksheet '$WorksheetName'. Columns found: $($rows[0].PSObject.Properties.Name -join ', ')"
    }
}

Write-Host "  $($rows.Count) rows read." -ForegroundColor Cyan

# ---------------------------------------------------------------------
# Resolve the target parent (probe OR group)
# ---------------------------------------------------------------------
# $parentId   = object id the groups are created under
# $parentKind = 'Probe' or 'Group', which decides the parameter New-PRTGGroup
#               receives and therefore the endpoint used.
if ($PSCmdlet.ParameterSetName -eq 'GroupId') {
    $parentId   = $ParentGroupId
    $parentKind = 'Group'

    # Check existence here so the error surfaces before the first group is
    # created.
    #
    # Deliberately -Id rather than -Filter: -Id hits GET /groups/{id} directly,
    # whereas a filter "id=..." goes to /experimental/groups and is rejected
    # with 400 Bad Request - "id" is not a valid filter field there.
    $parentGroup = $null
    try {
        $parentGroup = Get-PRTGGroup -Id $ParentGroupId | Select-Object -First 1
    }
    catch {
        throw "Group with id $ParentGroupId could not be read: $($_.Exception.Message)`nList groups with: Get-PRTGGroup | Select-Object id, name"
    }
    if (-not $parentGroup) {
        throw "Group with id $ParentGroupId was not found on the target system. List groups with: Get-PRTGGroup | Select-Object id, name"
    }
    Write-Host "Target group: '$($parentGroup.name)' (id $parentId)" -ForegroundColor Cyan
}
else {
    if ($PSCmdlet.ParameterSetName -eq 'ProbeName' -or -not $ParentProbeId) {
        $probeNameToResolve = if ($ParentProbeName) { $ParentProbeName } else { $rows[0].probe }

        Write-Host "Resolving target probe '$probeNameToResolve' ..." -ForegroundColor Cyan
        $probe = Get-PRTGProbe -Filter ('name = "{0}"' -f $probeNameToResolve) | Select-Object -First 1

        if (-not $probe) {
            throw "Probe '$probeNameToResolve' was not found on the target system. Pass -ParentProbeId or -ParentGroupId directly (see Get-PRTGProbe / Get-PRTGGroup)."
        }

        $ParentProbeId = $probe.id
    }

    $parentId   = $ParentProbeId
    $parentKind = 'Probe'
    Write-Host "Target probe id: $parentId" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------
# Determine the id of a newly created object
# ---------------------------------------------------------------------
# Per the OpenAPI spec the POST endpoints return the created object on 201. In
# practice PRTG sometimes sends an empty body. Relying on the return value
# alone makes the script skip an object that was in fact created - which then
# cascades, because every child of that object is skipped too.
#
# So: use the return value when present, otherwise look the object up - see
# lesson 5 on asynchrony.
function Resolve-CreatedObjectId {
    param(
        # Return value of the New-PRTG* cmdlet; may be $null, an object or an array
        [Parameter()][object]$Created,
        # Scriptblock looking the object up if the return value was empty
        [Parameter(Mandatory)][scriptblock]$Fallback,
        [Parameter()][int]$Attempts = 8,
        [Parameter()][int]$DelayMs = 750
    )

    if ($Created) {
        # Member enumeration would kick in on an array; take the first element
        # explicitly.
        $first = @($Created)[0]
        if ($first -and $first.id) { return [string]$first.id }
    }

    for ($i = 1; $i -le $Attempts; $i++) {
        $found = & $Fallback
        if ($found) {
            $f = @($found)[0]
            if ($f -and $f.id) {
                if ($i -gt 1) { Write-Verbose "Object found on attempt $i." }
                return [string]$f.id
            }
        }
        if ($i -lt $Attempts) { Start-Sleep -Milliseconds $DelayMs }
    }
    return $null
}

# ---------------------------------------------------------------------
# Step 1: groups
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 1: groups ---" -ForegroundColor Yellow

$groupNamesOrdered = [System.Collections.Specialized.OrderedDictionary]::new()
foreach ($row in $rows) {
    if ($row.group -and -not $groupNamesOrdered.Contains($row.group)) {
        $groupNamesOrdered[$row.group] = $true
    }
}

$existingGroups = @{}
Get-PRTGGroup -Filter ('parentid = "{0}"' -f $parentId) | ForEach-Object { $existingGroups[$_.name] = $_.id }

$groupIdMap = @{}
$summary    = [System.Collections.Generic.List[object]]::new()

foreach ($groupName in $groupNamesOrdered.Keys) {
    if ($existingGroups.ContainsKey($groupName)) {
        $groupIdMap[$groupName] = $existingGroups[$groupName]
        Write-Host "  [exists]  group '$groupName' (id $($existingGroups[$groupName]))"
        $summary.Add([pscustomobject]@{ Type = 'Group'; Name = $groupName; Action = 'Exists'; Id = $existingGroups[$groupName]; ParentId = $parentId })
        continue
    }

    if ($PSCmdlet.ShouldProcess("$parentKind $parentId", "Create group '$groupName'")) {
        $created = if ($parentKind -eq 'Group') {
            New-PRTGGroup -ParentGroupId $parentId -Name $groupName
        }
        else {
            New-PRTGGroup -ParentProbeId $parentId -Name $groupName
        }

        $newId = Resolve-CreatedObjectId -Created $created -Fallback {
            # Filter on parentid ONLY and compare the name in PowerShell
            # afterwards. A filter like 'parentid = "X" and name = "Y"' fails for
            # names containing ( ) [ ] & or non-ASCII characters, because
            # parentheses are grouping operators in the filter syntax - see
            # lesson 3.
            Get-PRTGGroup -Filter ('parentid = "{0}"' -f $parentId) |
                Where-Object { $_.name -ceq $groupName }
        }

        if ($newId) {
            $groupIdMap[$groupName] = $newId
            Write-Host "  [created] group '$groupName' (id $newId)" -ForegroundColor Green
            $summary.Add([pscustomobject]@{ Type = 'Group'; Name = $groupName; Action = 'Created'; Id = $newId; ParentId = $parentId })
        }
        else {
            Write-Warning "Group '$groupName' was created but was still not queryable after several attempts (about 6 s). Its devices are skipped - run the script again and they will be found."
            $summary.Add([pscustomobject]@{ Type = 'Group'; Name = $groupName; Action = 'Failed'; Id = $null; ParentId = $parentId })
        }
    }
}

# ---------------------------------------------------------------------
# Step 2: devices
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "--- Step 2: devices ---" -ForegroundColor Yellow

# A device usually has several sensor rows - reduce to exactly one row per
# device. Group and host are unique per device, which mirrors the PRTG tree:
# a device hangs below exactly one group.
$deviceRows = $rows | Group-Object -Property device | ForEach-Object {
    $first = $_.Group[0]
    [pscustomobject]@{
        Group  = $first.group
        Device = $first.device
        Host   = $first.host
    }
}

$existingDevicesByGroup = @{}

# Collects every device - existing and newly created - for step 3.
$deviceIdList = [System.Collections.Generic.List[object]]::new()

foreach ($deviceRow in $deviceRows) {
    if (-not $deviceRow.Group -or -not $groupIdMap.ContainsKey($deviceRow.Group)) {
        Write-Warning "Skipping device '$($deviceRow.Device)': group '$($deviceRow.Group)' was not created (for example under -WhatIf) or is empty."
        continue
    }
    $groupId = $groupIdMap[$deviceRow.Group]

    if (-not $existingDevicesByGroup.ContainsKey($groupId)) {
        $map = @{}
        Get-PRTGDevice -Filter ('parentid = "{0}"' -f $groupId) | ForEach-Object { $map[$_.name] = $_.id }
        $existingDevicesByGroup[$groupId] = $map
    }

    $deviceName = '{0} (IP: {1})' -f $deviceRow.Device, $deviceRow.Host

    if ($existingDevicesByGroup[$groupId].ContainsKey($deviceName)) {
        $existingId = $existingDevicesByGroup[$groupId][$deviceName]
        Write-Host "  [exists]  device '$deviceName' (id $existingId)"
        $summary.Add([pscustomobject]@{ Type = 'Device'; Name = $deviceName; Action = 'Exists'; Id = $existingId; ParentId = $groupId })
        $deviceIdList.Add([pscustomobject]@{ Id = $existingId; Name = $deviceName; ExcelDevice = $deviceRow.Device; Group = $deviceRow.Group })
        continue
    }

    $deviceSettings = $null
    if (-not $SkipSensorDiscovery -and $SensorDiscoveryMode -ne 'Manual') {
        $deviceSettings = @{ basic = @{ discoverytype = $discoveryTypeMap[$SensorDiscoveryMode] } }
    }

    if ($PSCmdlet.ShouldProcess("group $groupId", "Create device '$deviceName' ($($deviceRow.Host))")) {
        $newDeviceParams = @{
            ParentGroupId = $groupId
            Name          = $deviceName
            HostAddress   = $deviceRow.Host
        }
        if ($deviceSettings) { $newDeviceParams['Settings'] = $deviceSettings }

        $created = $null
        try {
            $created = New-PRTGDevice @newDeviceParams
        }
        catch {
            if ($deviceSettings) {
                Write-Warning "Creating '$deviceName' with the discoverytype setting failed ($($_.Exception.Message)). Retrying without it - sensors may have to be discovered manually."
                $created = New-PRTGDevice -ParentGroupId $groupId -Name $deviceName -HostAddress $deviceRow.Host
            }
            else {
                Write-Warning "Creating '$deviceName' failed: $($_.Exception.Message)"
            }
        }

        $newDeviceId = Resolve-CreatedObjectId -Created $created -Fallback {
            # Same reasoning as for groups - see lesson 3.
            Get-PRTGDevice -Filter ('parentid = "{0}"' -f $groupId) |
                Where-Object { $_.name -ceq $deviceName }
        }

        if ($newDeviceId) {
            $existingDevicesByGroup[$groupId][$deviceName] = $newDeviceId
            Write-Host "  [created] device '$deviceName' (id $newDeviceId)" -ForegroundColor Green
            $summary.Add([pscustomobject]@{ Type = 'Device'; Name = $deviceName; Action = 'Created'; Id = $newDeviceId; ParentId = $groupId })
            $deviceIdList.Add([pscustomobject]@{ Id = $newDeviceId; Name = $deviceName; ExcelDevice = $deviceRow.Device; Group = $deviceRow.Group })
        }
        else {
            Write-Warning "Device '$deviceName' was created but was still not queryable after several attempts (about 6 s). Run the script again and it will be found."
            $summary.Add([pscustomobject]@{ Type = 'Device'; Name = $deviceName; Action = 'Failed'; Id = $null; ParentId = $groupId })
        }
    }
}

# ---------------------------------------------------------------------
# Step 3: sensors (experimental endpoints - see .NOTES)
# ---------------------------------------------------------------------
if ($CreateSensors) {
    Write-Host ""
    Write-Host "--- Step 3: sensors ---" -ForegroundColor Yellow

    if ($deviceIdList.Count -eq 0) {
        Write-Warning "No devices known - sensor step skipped. (Normal under -WhatIf.)"
    }
    else {
        # Kind identifiers differ between PRTG versions. Rather than guessing,
        # read the list of types creatable on a real device and search in it.
        $referenceDeviceId = $deviceIdList[0].Id
        Write-Host "  Reading creatable sensor types (reference device id $referenceDeviceId) ..."

        $kindsResp = Invoke-PRTGRawRest -Path "/experimental/schemas/$referenceDeviceId" -QueryParameter @{ limit = 3000 }
        if ($kindsResp.StatusCode -ne 200) {
            throw "Could not read sensor types (HTTP $($kindsResp.StatusCode)): $($kindsResp.Raw)"
        }
        $allKinds = @($kindsResp.Content)
        Write-Host "  $($allKinds.Count) types reported, $(@($allKinds | Where-Object { $_.creatable }).Count) of them creatable."

        # Map by DISPLAY NAME, not by kind identifier - see lesson 6. The export
        # contains exactly these display names ("Ping", "Ping v2", "HTTP v2").
        $kindByDisplayName = @{}
        foreach ($k in $allKinds) {
            if ($k.creatable -and $k.name) {
                $key = "$($k.name)".Trim().ToLower()
                if (-not $kindByDisplayName.ContainsKey($key)) { $kindByDisplayName[$key] = $k }
            }
        }

        # -SensorKindFilter preselects which sensor names from the sheet are
        # considered at all.
        $relevantSheetNames = @($rows | ForEach-Object { "$($_.sensor)" } | Where-Object {
                $n = $_.ToLower()
                $hit = $false
                foreach ($f in $SensorKindFilter) { if ($n -like "*$($f.ToLower())*") { $hit = $true } }
                $hit
            } | Sort-Object -Unique)

        $resolvedKinds = [System.Collections.Generic.List[object]]::new()
        foreach ($sheetName in $relevantSheetNames) {
            $key = $sheetName.Trim().ToLower()
            if ($kindByDisplayName.ContainsKey($key)) {
                $k = $kindByDisplayName[$key]
                Write-Host ("  '{0}' -> kind '{1}'" -f $sheetName, $k.kind) -ForegroundColor Cyan
                $resolvedKinds.Add([pscustomobject]@{ SheetName = $sheetName; Kind = $k.kind; DisplayName = $k.name })
            }
            else {
                Write-Warning "Sheet sensor '$sheetName' has no type with exactly that display name on the target system - skipped."
            }
        }

        if ($resolvedKinds.Count -eq 0) {
            Write-Warning "Not a single sensor type could be resolved - step 3 aborted."
        }
        else {
            # Only sensors listed for this device in the sheet are created. No
            # ping row, no ping sensor.
            $sensorsByDevice = @{}
            foreach ($row in $rows) {
                if (-not $row.device) { continue }
                if (-not $sensorsByDevice.ContainsKey($row.device)) {
                    $sensorsByDevice[$row.device] = [System.Collections.Generic.List[string]]::new()
                }
                if ($row.sensor) { $sensorsByDevice[$row.device].Add([string]$row.sensor) }
            }

            foreach ($dev in $deviceIdList) {
                $wantedSensors = @()
                if ($sensorsByDevice.ContainsKey($dev.ExcelDevice)) {
                    $wantedSensors = @($sensorsByDevice[$dev.ExcelDevice])
                }

                # Read the device's existing sensors for idempotency.
                $haveResp = Invoke-PRTGRawRest -Path '/experimental/sensors' -QueryParameter @{ filter = ('parentid = "{0}"' -f $dev.Id); limit = 3000 }
                $haveNames = @()
                if ($haveResp.StatusCode -eq 200) {
                    $haveNames = @($haveResp.Content | ForEach-Object { "$($_.name)" })
                }
                else {
                    Write-Warning "Could not read sensors of '$($dev.Name)' (HTTP $($haveResp.StatusCode)) - creating anyway, possibly duplicating."
                }

                foreach ($rk in $resolvedKinds) {
                    # Is this sensor listed for this device, by exact sheet name?
                    $match = @($wantedSensors | Where-Object { $_.Trim() -ceq $rk.SheetName })
                    if ($match.Count -eq 0) { continue }

                    $sensorName = $rk.SheetName

                    if ($haveNames -contains $sensorName) {
                        Write-Host "  [exists]  $($dev.Name) -> '$sensorName'"
                        $summary.Add([pscustomobject]@{ Type = 'Sensor'; Name = "$($dev.Name) / $sensorName"; Action = 'Exists'; Id = $null; ParentId = $dev.Id })
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess("device $($dev.Id) ($($dev.Name))", "Create sensor '$sensorName' (kind $($rk.Kind))")) {
                        $body = @{ basic = @{ name = $sensorName } }
                        $r = Invoke-PRTGRawRest -Path "/experimental/devices/$($dev.Id)/sensor" -Method POST -QueryParameter @{ kindid = $rk.Kind } -Body $body

                        if ($r.StatusCode -eq 201 -or $r.StatusCode -eq 200) {
                            $newSensorId = $null
                            if ($r.Content) { $newSensorId = @($r.Content)[0].id }
                            Write-Host "  [created] $($dev.Name) -> '$sensorName'$(if ($newSensorId) { " (id $newSensorId)" })" -ForegroundColor Green
                            $summary.Add([pscustomobject]@{ Type = 'Sensor'; Name = "$($dev.Name) / $sensorName"; Action = 'Created'; Id = $newSensorId; ParentId = $dev.Id })
                        }
                        else {
                            Write-Warning "Sensor '$sensorName' on '$($dev.Name)' failed (HTTP $($r.StatusCode)): $($r.Raw)"
                            $summary.Add([pscustomobject]@{ Type = 'Sensor'; Name = "$($dev.Name) / $sensorName"; Action = 'Failed'; Id = $null; ParentId = $dev.Id })
                        }
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Yellow
$summary | Group-Object Type, Action | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-28} {1}" -f $_.Name, $_.Count)
}

if ($ExportCsv) {
    $summary | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host ""
    Write-Host "Log written to: $ExportCsv" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# What happens to sensors now
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "--- Note on sensors ---" -ForegroundColor Yellow
if ($SkipSensorDiscovery) {
    Write-Host "  -SkipSensorDiscovery was set, so no auto-discovery setting was applied to" -ForegroundColor Yellow
    Write-Host "  the new devices. Discover sensors manually in the PRTG interface, or run" -ForegroundColor Yellow
    Write-Host "  this script again with -CreateSensors to create exactly the sensors listed" -ForegroundColor Yellow
    Write-Host "  in the sheet." -ForegroundColor Yellow
}
else {
    Write-Host "  New devices were created with discoverytype='$SensorDiscoveryMode', so PRTG" -ForegroundColor Yellow
    Write-Host "  discovers sensors on its own - INCLUDING ones the sheet does not list. To" -ForegroundColor Yellow
    Write-Host "  end up with the sheet's sensors and nothing else, run with" -ForegroundColor Yellow
    Write-Host "  -SkipSensorDiscovery -CreateSensors instead." -ForegroundColor Yellow
}
