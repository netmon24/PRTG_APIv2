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
#
# $env:ProgramFiles is NOT usable here: in a 32-bit PowerShell host it expands
# to "C:\Program Files (x86)", and a module installed there is invisible to the
# 64-bit console people actually use. $env:ProgramW6432 always names the 64-bit
# tree, whatever the host's bitness.
if ($onWindows) {
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
        Write-Warning "Running in a 32-bit PowerShell host. Installing into the 64-bit module tree so the normal console finds the module."
    }

    $root = if ($Scope -eq 'AllUsers') {
        if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    }
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

# -RemoveOldVersions only ever touches the target scope. Copies in another
# scope - a different Program Files tree, a user's Documents folder - stay, and
# that is deliberate: this script must not delete from locations the caller did
# not ask for.
if ($RemoveOldVersions -and (Test-Path -LiteralPath $moduleRoot)) {
    foreach ($old in Get-ChildItem -LiteralPath $moduleRoot -Directory | Where-Object Name -ne $version) {
        if ($PSCmdlet.ShouldProcess($old.FullName, 'Remove old version')) {
            Remove-Item -LiteralPath $old.FullName -Recurse -Force
            Write-Host "Removed old version $($old.Name)" -ForegroundColor Yellow
        }
    }
}

if (-not $WhatIfPreference) {
    $installed = @(Get-Module -ListAvailable -Name PRTG.PowerShell)

    if ($installed | Where-Object Version -eq $version) {
        Write-Host "Run 'Import-Module PRTG.PowerShell -Force' to load it." -ForegroundColor Cyan
    }
    else {
        Write-Warning "Files copied, but PowerShell does not list the module. Check that '$base' is in `$env:PSModulePath."
    }

    # Copies outside the target are the reason a fix can appear not to work:
    # PowerShell loads the highest version it can see, which may be an old one
    # in a tree this run never touched. Name them rather than leave the caller
    # to discover them weeks later.
    $elsewhere = @($installed | Where-Object { $_.ModuleBase -notlike "$moduleRoot*" })
    if ($elsewhere.Count -gt 0) {
        Write-Warning "Other copies of this module are installed outside the target location:"
        foreach ($other in $elsewhere | Sort-Object Version) {
            Write-Warning ("  {0}  {1}" -f $other.Version, $other.ModuleBase)
        }
        Write-Warning "PowerShell loads the highest version it finds anywhere. Remove the ones you do not want, or they will keep shadowing this install."
    }
}
