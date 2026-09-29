<#
    .SYNOPSIS
    Reports where settings inheritance is overridden in the PRTG object tree.

    .DESCRIPTION
    Lists groups, devices and probes - optionally sensors - whose settings no
    longer inherit from their parent, using Get-PRTGInheritanceBreak.

    If the session already holds a PRTG connection, that connection is reused
    and -ComputerName is not needed. Otherwise the script connects, asking for
    the API key interactively.

    .PARAMETER ComputerName
    PRTG core server, e.g. 'prtg.example.com'. Required only when no
    connection is active yet.

    .PARAMETER Port
    Overrides the module's default API port. Rarely needed.

    .PARAMETER SkipCertificateCheck
    Skips TLS validation, e.g. for self-signed certificates.

    .PARAMETER IncludeSensors
    Includes sensors. Expect many more hits, since individual sensor limits
    are often intentional.

    .PARAMETER ExportCsv
    Writes the result to this path as semicolon-separated CSV.

    .EXAMPLE
    .\Find-PRTGInheritanceBreaks.ps1 -ComputerName prtg.example.com

    .EXAMPLE
    Connect-PRTGServer -ComputerName prtg.example.com -ApiToken $token
    .\Find-PRTGInheritanceBreaks.ps1 -IncludeSensors

    Reuses the existing connection.
#>
#requires -Modules PRTG.PowerShell
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port,

    [Parameter()]
    [switch]$SkipCertificateCheck,

    [Parameter()]
    [switch]$IncludeSensors,

    [Parameter()]
    [string]$ExportCsv
)

Import-Module PRTG.PowerShell -ErrorAction Stop

# Test-PRTGServerHealth returns $false instead of throwing when no session
# exists or the server is unreachable, so the warning is suppressed here.
if (-not (Test-PRTGServerHealth -WarningAction SilentlyContinue)) {

    if (-not $ComputerName) {
        throw "No active PRTG connection. Run Connect-PRTGServer first, or pass -ComputerName."
    }

    # Stored credentials are deliberately not used; the key is asked for here.
    $connectParams = @{
        ComputerName         = $ComputerName
        ApiToken             = Read-Host -AsSecureString -Prompt "PRTG API key for $ComputerName"
        SkipCertificateCheck = $SkipCertificateCheck
    }
    # Only override the module's default port when the caller asked for it.
    if ($PSBoundParameters.ContainsKey('Port')) { $connectParams['Port'] = $Port }

    Connect-PRTGServer @connectParams
}

Write-Host "Searching the PRTG tree for broken inheritance ..." -ForegroundColor Cyan

$results = Get-PRTGInheritanceBreak -ObjectType All -IncludeSensors:$IncludeSensors

if (-not $results -or $results.Count -eq 0) {
    $scope = "groups, devices, probes$(if ($IncludeSensors) { ', sensors' })"
    Write-Host "No broken inheritance found (checked: $scope)." -ForegroundColor Green
    return
}

Write-Host ""
Write-Host "Broken inheritance found: $($results.Count)" -ForegroundColor Yellow
Write-Host ""

$results | Sort-Object Type, Name |
    Format-Table -Property Type, Name, Id, BrokenSection, Path -AutoSize -Wrap

Write-Host ""
Write-Host "Summary by settings section:" -ForegroundColor Cyan
$results | Group-Object BrokenSection | Sort-Object Count -Descending |
    Format-Table -Property Count, Name -AutoSize

if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host ""
    Write-Host "Exported to: $ExportCsv" -ForegroundColor Green
}
