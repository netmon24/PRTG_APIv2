<#
    .SYNOPSIS
    Installs or updates the PRTG.PowerShell module from a local copy of this
    repository. No internet access required.

    .DESCRIPTION
    Copies the module into a version folder whose name is read from the
    manifest rather than hard-coded, which is the usual reason a manual
    installation fails silently. The same call serves both first installation
    and every later update. Background: see README, section Installation.

    .PARAMETER SourcePath
    Repository root, extracted ZIP, or the module folder itself. Defaults to
    the repository this script lives in.

    .PARAMETER Scope
    CurrentUser (default) needs no administrative rights. AllUsers installs
    machine-wide and requires an elevated session on Windows.

    .PARAMETER RemoveOldVersions
    Deletes all other installed versions in the target scope after a
    successful copy.

    .PARAMETER Force
    Overwrites an already installed identical version.

    .EXAMPLE
    .\Scripts\Install-PRTGPowerShell.ps1

    Installs into the current user's module folder.

    .EXAMPLE
    .\Scripts\Install-PRTGPowerShell.ps1 -Scope AllUsers -RemoveOldVersions

    Installs machine-wide and removes older versions afterwards.

    .EXAMPLE
    .\Scripts\Install-PRTGPowerShell.ps1 -WhatIf

    Shows what would happen without changing anything.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePath,

    [Parameter()]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [Parameter()]
    [switch]$RemoveOldVersions,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShell 5.1 does not define $IsWindows; its absence means Windows.
$onWindows = (-not (Test-Path Variable:IsWindows)) -or $IsWindows

if (-not $SourcePath) { $SourcePath = Split-Path -Parent $PSScriptRoot }

$manifest = Get-ChildItem -Path $SourcePath -Filter 'PRTG.PowerShell.psd1' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } |
    Select-Object -First 1

if (-not $manifest) {
    throw "No PRTG.PowerShell.psd1 found below '$SourcePath'. Point -SourcePath at the repository root or the extracted ZIP."
}

$moduleSource = $manifest.Directory.FullName
$version      = (Import-PowerShellDataFile -LiteralPath $manifest.FullName).ModuleVersion

Write-Verbose "Source $moduleSource, version $version"

# Destination follows two independent axes: the root (per scope) and the
# edition folder, which differs between Windows PowerShell and PowerShell 7+.
if ($onWindows) {
    $root = if ($Scope -eq 'AllUsers') { $env:ProgramFiles }
            else { [Environment]::GetFolderPath('MyDocuments') }

    $edition = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'WindowsPowerShell' } else { 'PowerShell' }
    $base    = Join-Path $root (Join-Path $edition 'Modules')
}
else {
    $base = if ($Scope -eq 'AllUsers') { '/usr/local/share/powershell/Modules' }
            else { Join-Path $HOME '.local/share/powershell/Modules' }
}

$moduleRoot  = Join-Path $base 'PRTG.PowerShell'
$destination = Join-Path $moduleRoot $version

# Fail on missing privileges before anything is written.
if ($Scope -eq 'AllUsers' -and $onWindows) {
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "-Scope AllUsers writes to '$base' and needs an elevated session. Run PowerShell as administrator, or use -Scope CurrentUser."
    }
}

$alreadyInstalled = Test-Path -LiteralPath $destination

if ($alreadyInstalled -and -not $Force) {
    throw "Version $version is already installed at '$destination'. Use -Force to overwrite it."
}

if ($PSCmdlet.ShouldProcess($destination, "Install PRTG.PowerShell $version")) {

    if ($alreadyInstalled) { Remove-Item -LiteralPath $destination -Recurse -Force }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path (Join-Path $moduleSource '*') -Destination $destination -Recurse -Force

    # Files from a downloaded ZIP carry the mark-of-the-web, which stops
    # PowerShell from loading them.
    if ($onWindows) {
        Get-ChildItem -LiteralPath $destination -Recurse -File | Unblock-File
    }

    Write-Host "Installed PRTG.PowerShell $version to $destination" -ForegroundColor Green
}

if ($RemoveOldVersions -and (Test-Path -LiteralPath $moduleRoot)) {
    foreach ($old in Get-ChildItem -LiteralPath $moduleRoot -Directory | Where-Object Name -ne $version) {
        if ($PSCmdlet.ShouldProcess($old.FullName, 'Remove old version')) {
            Remove-Item -LiteralPath $old.FullName -Recurse -Force
            Write-Host "Removed old version $($old.Name)" -ForegroundColor Yellow
        }
    }
}

if (-not $WhatIfPreference) {
    $found = Get-Module -ListAvailable -Name PRTG.PowerShell |
        Where-Object Version -eq $version

    if ($found) {
        Write-Host "Run 'Import-Module PRTG.PowerShell -Force' to load it." -ForegroundColor Cyan
    }
    else {
        Write-Warning "Files copied, but PowerShell does not list the module. Check that '$base' is in `$env:PSModulePath."
    }
}
