# PRTG.PowerShell

> A PowerShell module for the **PRTG Network Monitor API v2** (REST/OpenAPI).  
> Developed and maintained by [netmon24 GmbH & Co. KG](https://netmon24.eu).

## Install

```powershell
git clone https://github.com/netmon24/PRTG_APIv2.git
cd PRTG_APIv2
.\Scripts\Install-PRTGPowerShell.ps1
Import-Module PRTG.PowerShell
```

No internet access needed beyond the clone — copy the folder to the target machine and the same call works there. [Installation in detail](#installation-in-detail) covers the manual route, updating and uninstalling; [Troubleshooting](#troubleshooting) covers what to do when it does not work.

---

## Overview

This module wraps the official PRTG API v2 and provides 28 PowerShell cmdlets for the most common administrative tasks:

- **Connect/Disconnect** — API key (recommended) or username/password fallback
- **Get-** — Devices, Groups, Probes, Sensors, Channels, Objects, Timeseries, Counts, Status summary
- **New-** — Devices, Groups
- **Set-** — Devices, Groups
- **Remove-** — Devices, Groups, Probes
- **Suspend-/Resume-** — Devices, Groups, Probes (with `Pause-*` aliases matching PRTG terminology)
- **Start-PRTGScan** — Trigger immediate scan for Devices, Groups, Probes
- **Move-PRTGObject** — Move objects within the hierarchy
- **Get-PRTGInheritanceBreak** — Find objects with broken settings inheritance
- **Test-PRTGServerHealth** — Quick reachability check

### Ready-to-run scripts

| Script | Description |
|---|---|
| `Scripts/Find-PRTGInheritanceBreaks.ps1` | Lists all objects where settings inheritance has been overridden, with optional CSV export |

---

## Requirements

- Windows PowerShell **5.1** or PowerShell **7+**
- PRTG Network Monitor with **API v2 enabled** (PRTG 21.4.73 or newer)
- An API key created in PRTG under *Setup → Account Settings → API Keys*

---

## Quick Start

```powershell
# Connect with API key (recommended)
$token = Read-Host -AsSecureString -Prompt 'PRTG API Key'
Connect-PRTGServer -ComputerName 'prtg.example.com' -ApiToken $token

# Connect with username/password (fallback)
Connect-PRTGServer -ComputerName 'prtg.example.com' -Credential (Get-Credential)

# Skip certificate check (e.g. during certificate migration)
Connect-PRTGServer -ComputerName 'prtg.example.com' -ApiToken $token -SkipCertificateCheck

# List all devices with status Down
Get-PRTGDevice -Filter 'status=Down'

# Pause a device for maintenance
Suspend-PRTGDevice -Id 2322 -Message 'Maintenance window'

# Resume it afterwards
Resume-PRTGDevice -Id 2322

# Find all objects where inheritance is broken
Get-PRTGInheritanceBreak

# Run the full inheritance report with CSV export - reuses the connection above
.\Scripts\Find-PRTGInheritanceBreaks.ps1 -ExportCsv C:\Temp\inheritance.csv

# Disconnect
Disconnect-PRTGServer
```

Full cmdlet help is available via `Get-Help <CmdletName> -Full`.

---

## Cmdlet Reference

### Connection

| Cmdlet | Description |
|---|---|
| `Connect-PRTGServer` | Connect to a PRTG core server (API key or credential) |
| `Disconnect-PRTGServer` | Disconnect and clear the stored token |

### Read (Get-)

| Cmdlet | Description |
|---|---|
| `Get-PRTGDevice` | Read one device by ID or a filtered list |
| `Get-PRTGGroup` | Read one group by ID or a filtered list |
| `Get-PRTGProbe` | Read one probe by ID or a filtered list |
| `Get-PRTGSensor` | Read sensors (via objects endpoint with type filter) |
| `Get-PRTGChannel` | Read channels by ID or list |
| `Get-PRTGObject` | Generic read across all object types |
| `Get-PRTGObjectCount` | Number of objects per type (capacity/license check) |
| `Get-PRTGSensorStatusSummary` | Global sensor status counts (Up/Down/Warning/...) |
| `Get-PRTGTimeseries` | Historical measurements (Live/Short/Medium/Long) |
| `Get-PRTGInheritanceBreak` | Find objects with overridden (broken) inheritance |

### Create (New-)

| Cmdlet | Description |
|---|---|
| `New-PRTGDevice` | Create a device under a group or probe |
| `New-PRTGGroup` | Create a group under a group or probe |

### Modify (Set-)

| Cmdlet | Description |
|---|---|
| `Set-PRTGDevice` | Change device settings (name, host, custom settings) |
| `Set-PRTGGroup` | Change group settings |

### Delete (Remove-)

| Cmdlet | Description |
|---|---|
| `Remove-PRTGDevice` | Permanently delete a device and all child sensors |
| `Remove-PRTGGroup` | Permanently delete a group and all children |
| `Remove-PRTGProbe` | Permanently delete a probe and all children |

### Pause / Resume (Suspend-/Resume-)

| Cmdlet | Aliases | Description |
|---|---|---|
| `Suspend-PRTGDevice` | `Pause-PRTGDevice` | Pause a device (single or by filter) |
| `Resume-PRTGDevice` | — | Resume a paused device |
| `Suspend-PRTGGroup` | `Pause-PRTGGroup` | Pause a group |
| `Resume-PRTGGroup` | — | Resume a paused group |
| `Suspend-PRTGProbe` | `Pause-PRTGProbe` | Pause a probe |
| `Resume-PRTGProbe` | — | Resume a paused probe |

> **Why Suspend- instead of Pause-?**  
> PowerShell only allows [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands). `Pause` is not on the list; `Suspend` is. The `Pause-*` aliases are provided for convenience.

### Actions

| Cmdlet | Description |
|---|---|
| `Start-PRTGScan` | Trigger immediate scan for device, group, or probe |
| `Move-PRTGObject` | Move an object to a new parent or reorder it |
| `Test-PRTGServerHealth` | Returns `$true` if the PRTG server is reachable and licensed |

---

## Installation in detail

### Option A — Install script

The script reads the version from the manifest, creates the matching folder, removes the mark-of-the-web and verifies the result. The same call performs the first installation and every later update.

```powershell
# From a downloaded ZIP, unblock FIRST - otherwise the execution policy refuses
# to run the installer itself, and it cannot unblock what it never started
Get-ChildItem . -Recurse -File | Unblock-File

.\Scripts\Install-PRTGPowerShell.ps1                   # current user, no admin rights
.\Scripts\Install-PRTGPowerShell.ps1 -Scope AllUsers   # machine-wide, elevated session
.\Scripts\Install-PRTGPowerShell.ps1 -WhatIf           # dry run
```

On Windows the script always installs into the 64-bit module tree, even when started from a 32-bit PowerShell, and warns when it had to correct for that. After installing it also lists any copies it found in other module roots, because those shadow the new one.

| Parameter | Effect |
|---|---|
| `-Scope CurrentUser` \| `AllUsers` | Target location. Default `CurrentUser`. `AllUsers` needs an elevated session. |
| `-SourcePath <path>` | Where the module files are. Defaults to the repository the script lives in. |
| `-RemoveOldVersions` | Deletes other installed versions **in the target scope** after a successful copy. Copies in another module root are reported, never deleted. |
| `-Force` | Overwrites an already installed identical version. |

`Get-Help .\Scripts\Install-PRTGPowerShell.ps1 -Full` has the rest.

### Option B — Manual installation

For machines where script execution is blocked by policy.

```powershell
# The folder name must match ModuleVersion exactly, so read it - do not type it
$version = (Import-PowerShellDataFile .\PRTG.PowerShell\PRTG.PowerShell.psd1).ModuleVersion

# First entry of PSModulePath is the current user's module folder,
# correct for both Windows PowerShell 5.1 and PowerShell 7+
$base = ($env:PSModulePath -split [IO.Path]::PathSeparator)[0]
$dest = Join-Path $base "PRTG.PowerShell\$version"

New-Item -ItemType Directory -Path $dest -Force
Copy-Item .\PRTG.PowerShell\* -Destination $dest -Recurse -Force
Get-ChildItem $dest -Recurse -File | Unblock-File

Import-Module PRTG.PowerShell -Force
Get-Command -Module PRTG.PowerShell
```

The manifest must end up **directly** in the version folder — `...\1.1.0\PRTG.PowerShell.psd1`, not `...\1.1.0\PRTG.PowerShell\PRTG.PowerShell.psd1`.

### Working from a clone

For development, skip installing altogether and import the manifest by path. The module is gone when the session ends.

```powershell
Import-Module .\PRTG.PowerShell\PRTG.PowerShell.psd1 -Force
```

### Updating

An update is an installation into a new version folder.

```powershell
Get-Module -ListAvailable -Name PRTG.PowerShell | Select-Object Version, ModuleBase
.\Scripts\Install-PRTGPowerShell.ps1 -RemoveOldVersions
```

Several versions may coexist; PowerShell loads the highest one, so `-RemoveOldVersions` is tidiness rather than a requirement. A session that already loaded the module keeps the old version — use `Import-Module PRTG.PowerShell -Force` or open a new window. That is the usual reason an update appears not to have worked.

### Uninstalling

```powershell
$module = Get-Module -ListAvailable -Name PRTG.PowerShell
Remove-Module PRTG.PowerShell -ErrorAction SilentlyContinue
$module.ModuleBase | Split-Path -Parent | Select-Object -Unique | Remove-Item -Recurse -Force
```

> **Windows Server note:** PowerShell 5.1 reads `.ps1` files as UTF-8 only when a **BOM** (Byte Order Mark) is present. All files in this repository include the UTF-8 BOM. Do **not** re-save them as UTF-8 without BOM or as ANSI — that will corrupt German umlauts and break the parser.

---

## Architecture

```
PRTG.PowerShell/           ← Module folder (copy its CONTENTS to Modules\PRTG.PowerShell\<ModuleVersion>\)
├── PRTG.PowerShell.psd1   ← Module manifest (version, exports, aliases)
├── PRTG.PowerShell.psm1   ← Loader (dot-sources Private\ and Public\)
├── Private\
│   ├── PRTGSession.ps1            ← In-memory session state (Set/Get/Clear)
│   ├── Invoke-PRTGRestMethod.ps1  ← Central HTTP engine (auth, cert bypass, error handling)
│   └── Get-PRTGPagedResult.ps1    ← Automatic pagination (offset/limit)
└── Public\
    └── *.ps1              ← One file per cmdlet (28 total)

Scripts\
├── Install-PRTGPowerShell.ps1       ← Offline installer / updater
└── Find-PRTGInheritanceBreaks.ps1   ← Standalone report script
```

### Key implementation notes

- **UTF-8 BOM** — All `.ps1`/`.psm1`/`.psd1` files carry a UTF-8 BOM so that Windows PowerShell 5.1 correctly parses German characters.
- **Certificate bypass** — Implemented via `ServicePointManager` callback for PS 5.1 and the native `-SkipCertificateCheck` for PS 7+.
- **Automatic paging** — `Get-PRTGPagedResult` loops with increasing `offset` until the API returns fewer items than the page size (default: 500).
- **PRTG error bodies** — `Invoke-PRTGRestMethod` parses the structured PRTG error JSON (`code`, `message`, `request_id`) for readable error messages.

---

## Known Limitations

- The `inheritance` include parameter is described by Paessler as not fully stable yet. If `Get-PRTGInheritanceBreak` returns unexpected results on your PRTG version, run `Get-PRTGGroup -Id <id> -Include all_sections,inheritance | ConvertTo-Json -Depth 10` and open an issue with the output so the detection logic can be adjusted.
- No Sensor-specific write endpoints (Set-PRTGSensor, New-PRTGSensor) — the PRTG API v2 does not yet fully expose these.
- Clusters are not supported by PRTG API v2 itself.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot find path ...\PRTG.PowerShell\*` / *Der Pfad … kann nicht gefunden werden* | A GitHub ZIP extracts into a wrapper folder such as `PRTG.PowerShell-main`; the module folder is one level further down | `cd` into the extracted folder first, or pass `-SourcePath` to the install script |
| `The specified module 'PRTG.PowerShell' was not loaded because no valid module file was found` / *… wurde nicht geladen, da in keinem Modulverzeichnis eine gültige Moduldatei gefunden wurde* | Version folder name does not match `ModuleVersion`, or one folder level too many | Compare the folder name with `(Import-PowerShellDataFile ...psd1).ModuleVersion`; the manifest must sit **directly** in the version folder |
| `Access to the path ... is denied` / *Zugriff verweigert* | Writing to `C:\Program Files` without elevation | Start PowerShell as administrator, or install with `-Scope CurrentUser` |
| `... cannot be loaded because running scripts is disabled on this system` | Execution policy blocks local scripts | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` for the current session only |
| `... is not digitally signed`, execution policy is `RemoteSigned` | Mark-of-the-web on files from a downloaded ZIP | `Get-ChildItem . -Recurse -File \| Unblock-File` in the extracted folder, **before** running any script from it |
| `... is not digitally signed`, execution policy is `AllSigned` | `AllSigned` requires a signature even for local files, so unblocking does not help | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`. If `Get-ExecutionPolicy -List` shows `AllSigned` under `MachinePolicy` or `UserPolicy` it comes from Group Policy and the process scope **cannot** override it - use [Option B](#option-b--manual-installation) and paste the commands into the console, which the execution policy does not restrict |
| Module installed, but the normal console does not see it | The install ran in a **32-bit** PowerShell, which puts `$env:ProgramFiles` at `C:\Program Files (x86)`; the 64-bit console does not look there | Current versions of the install script always target the 64-bit tree and warn about this. To check: `Get-Module -ListAvailable PRTG.PowerShell \| Select-Object Version, ModuleBase` |
| A fix appears to have no effect | An older copy in **another** module root shadows the new one - PowerShell loads the highest version it finds anywhere, and `-RemoveOldVersions` only cleans the target scope | `Get-Module -ListAvailable PRTG.PowerShell \| Select-Object Version, ModuleBase` lists every copy; delete the ones you do not want |
| Cmdlets still behave like the old version | Old module still loaded in the session | `Import-Module PRTG.PowerShell -Force`, or open a new window |
| German umlauts appear garbled | Files re-saved without UTF-8 BOM | Restore the original files; PowerShell 5.1 needs the BOM |

---

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 netmon24 GmbH & Co. KG.
