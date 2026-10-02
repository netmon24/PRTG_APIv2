# Changelog

All notable changes to this project will be documented in this file.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
This project uses [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **`Scripts/Install-PRTGPowerShell.ps1`** — offline installer and updater. Reads
  the version from the manifest, creates the correctly named version folder,
  removes the mark-of-the-web and verifies the result. Supports `-Scope`
  (`CurrentUser`/`AllUsers`), `-SourcePath`, `-RemoveOldVersions`, `-Force` and
  `-WhatIf`. The same command covers first installation and every later update.
- README sections **Updating**, **Uninstalling** and **Troubleshooting**, the
  latter mapping the common error messages (wrong version folder, ZIP wrapper
  folder, missing elevation, execution policy, mark-of-the-web) to their cause
  and fix.

### Fixed
- **The installer wrote to the wrong Program Files tree in a 32-bit host.**
  `$env:ProgramFiles` expands to `C:\Program Files (x86)` there, and a module
  installed in that tree is invisible to the 64-bit console. It now uses
  `$env:ProgramW6432`, which always names the 64-bit tree, and warns when it
  had to correct for a 32-bit host. Found on a real Windows Server, where it
  produced three parallel installations and a fix that appeared not to work.
- The installer now reports copies of the module found in **other** module
  roots. `-RemoveOldVersions` only cleans the target scope - by design, since
  it must not delete from locations the caller did not name - so an old copy
  elsewhere kept shadowing the new install with nothing pointing at it.
  Its parameter description now says so instead of claiming it removes all
  other versions.
- README attributed `is not digitally signed` to the mark-of-the-web alone. An
  `AllSigned` execution policy produces the identical message and needs a
  completely different remedy - and when it comes from Group Policy, the
  process scope cannot override it at all, leaving the manual installation as
  the only route. Both cases are now listed separately, along with the 32-bit
  tree and the shadowing-copy symptoms.
- README told readers to run the install script before unblocking the files,
  which cannot work: the execution policy refuses to start the installer, and
  an installer that never started cannot unblock anything. `Unblock-File` now
  comes first.
- **Comment-based help in both scripts was never parsed.** A `#requires`
  statement placed *above* the help block stops PowerShell from recognising it,
  so `Get-Help` returned the bare syntax line instead of the documented
  parameters and examples. The help block now comes first and `#requires`
  directly after it, which keeps the requirement in force.
- `Scripts/Find-PRTGInheritanceBreaks.ps1` declared its own default API port,
  duplicating the one `Connect-PRTGServer` already owns together with
  `[ValidateRange(1,65535)]` — the same duplication that produced the stale
  `8443` fixed in 1.1.0. The parameter now overrides the module default only
  when the caller passes it.
- `-ComputerName` was `Mandatory` although the help states it is ignored when a
  session already exists, so PowerShell prompted for a value it then discarded.
  It is now required only where it is actually used, with a message naming
  `Connect-PRTGServer` as the alternative.
- README listed `en-US\*` as part of a correct installation, but that folder is
  empty — the documented "must look exactly like this" layout was unreachable.
- README's manual installation hard-coded the Windows PowerShell 5.1 module path
  directly below a table offering four paths, so a PowerShell 7 user copying it
  installed into the wrong tree. It is now derived from `$env:PSModulePath`.
- Uninstall instructions hard-coded that path again instead of using the
  `ModuleBase` the preceding command had just determined.

### Changed
- **`Scripts/Find-PRTGInheritanceBreaks.ps1` takes parameters** instead of a
  hard-coded configuration block: `-ComputerName`, `-Port`,
  `-SkipCertificateCheck`. The hard-coded server and port (`8443` — the classic
  web server, which does not answer API v2 requests) are gone.
- `Scripts/` is English throughout, matching the README. The module itself
  remains German for now.
- `Scripts/Install-PRTGPowerShell.ps1` reduced from 211 to 148 lines with no
  loss of function: section banners removed, `.DESCRIPTION` shortened, the
  four-way platform branch replaced by two independent axes, overlapping input
  checks merged, error messages cut to cause and remedy.
- Documentation consolidated and shortened. The root `README.md` is the single
  complete reference (327 → 282 lines) and `PRTG.PowerShell/README.md` points to
  it; both previously carried diverging install instructions still naming
  version `1.0.0`. The install command now sits near the top, the rule about the
  version folder went from seven places to two, the module path table and a
  dramatised warning box were dropped, and Troubleshooting moved to the end
  where a lookup table belongs.
- The install script is no longer listed under "Ready-to-run scripts" — it is
  tooling, not a PRTG feature.
- Manifest `ProjectUri` now points at the repository instead of Paessler's API
  specification.

### Removed
- Internal host names from examples, cmdlet help and scripts; replaced by
  `prtg.example.com`.
- A `.DS_Store` cleanup step in the installer that could never trigger for
  users — the file is in `.gitignore` and untracked, so it reaches neither a
  clone nor a ZIP.

---

## [1.1.0] — 2026-09-26

### Fixed
- **`-SkipCertificateCheck` was non-functional on Windows PowerShell 5.1.** The
  certificate validation callback was assigned from a method reference
  (`[PRTG.CertificateValidationBypass]::Validate`), which PS 5.1 resolves to a
  `PSMethod` object. Assignment failed with *"Cannot convert ... PSMethod to type
  RemoteCertificateValidationCallback"* — method-group conversion only exists
  from PowerShell 6 onwards. Now assigned via
  `[System.Delegate]::CreateDelegate(...)`, which yields a real compiled
  delegate.

  A ScriptBlock is **not** a valid alternative here: PowerShell compiles it into
  a lambda that requires a Runspace at call time, but .NET invokes the callback
  on a background thread that has none. The resulting *"There is no Runspace
  available to run scripts in this thread"* surfaces to the caller as the
  misleading *"The underlying connection was closed: An unexpected error
  occurred on a send."* Both failed variants are documented inline so they are
  not reintroduced.

- **Umlauts and other non-ASCII characters in the request body were corrupted.**
  `Invoke-RestMethod` on Windows PowerShell 5.1 encodes a string body as
  ISO-8859-1 when no charset is given. Device names containing `Domäne` were
  stored in PRTG as `Dom?ne`. The body is now passed as UTF-8 bytes with
  `ContentType = 'application/json; charset=utf-8'`.

### Added
- TLS 1.2 is enabled additively (`-bor`) in the PS 5.1 branch. Older Windows
  builds still negotiate TLS 1.0, which PRTG rejects.

### Changed — BREAKING
- **`Connect-PRTGServer` default `-Port` changed from `443` to `1616`.** PRTG
  API v2 is served by the PRTG Application Server on **1616** (HTTPS) / 1615
  (HTTP). Port 443 is the classic web server: every `/api/v2/*` path answers
  `302` to the login page, and a Bearer header yields
  `401 Unsupported authorization scheme` — failure modes that point at TLS
  rather than at the port, which is what makes this so costly to diagnose.

  **Migration:** scripts that relied on the old default and connect to a
  non-standard port must now pass `-Port` explicitly. Scripts that already
  passed `-Port` are unaffected.

  Examples in the help and both READMEs now use the default port.

---

## [1.0.0] — 2026-06-17

### Added
- `Connect-PRTGServer` — API key (SecureString) and credential (username/password) authentication, `-SkipCertificateCheck`, PS 5.1 and PS 7+ compatibility
- `Disconnect-PRTGServer` — clears the in-memory session token
- `Get-PRTGDevice` — single device by ID or paginated filtered list
- `Get-PRTGGroup` — single group by ID or paginated filtered list
- `Get-PRTGProbe` — single probe by ID or paginated filtered list
- `Get-PRTGSensor` — sensor lookup via `/experimental/objects` with automatic `type=sensor` filter
- `Get-PRTGChannel` — single channel by ID (`<sensorId>.<index>`) or list
- `Get-PRTGObject` — generic read across all object types
- `Get-PRTGObjectCount` — object counts per type
- `Get-PRTGSensorStatusSummary` — global sensor status distribution
- `Get-PRTGTimeseries` — historical measurements (Live / Short / Medium / Long), auto-converts array-of-arrays to named PSCustomObjects
- `Get-PRTGInheritanceBreak` — finds objects with overridden settings inheritance using `include=all_sections,inheritance`
- `New-PRTGDevice` — create a device under a group or probe
- `New-PRTGGroup` — create a group under a group or probe
- `Set-PRTGDevice` — PATCH device settings (name, host, arbitrary settings hashtable)
- `Set-PRTGGroup` — PATCH group settings
- `Remove-PRTGDevice` — DELETE device with ConfirmImpact High
- `Remove-PRTGGroup` — DELETE group with ConfirmImpact High
- `Remove-PRTGProbe` — DELETE probe with ConfirmImpact High
- `Suspend-PRTGDevice` (alias `Pause-PRTGDevice`) — pause single device or filtered set
- `Resume-PRTGDevice` — resume single device or filtered set
- `Suspend-PRTGGroup` (alias `Pause-PRTGGroup`) — pause group
- `Resume-PRTGGroup` — resume group
- `Suspend-PRTGProbe` (alias `Pause-PRTGProbe`) — pause probe
- `Resume-PRTGProbe` — resume probe
- `Start-PRTGScan` — immediate scan for device, group, or probe (single or filtered)
- `Move-PRTGObject` — move object to new parent or reorder by position/preset
- `Test-PRTGServerHealth` — returns `$true`/`$false` based on `/health` endpoint
- Private helpers: `PRTGSession.ps1` (in-memory token store), `Invoke-PRTGRestMethod.ps1` (HTTP engine), `Get-PRTGPagedResult.ps1` (automatic paging)
- Standalone script `Scripts/Find-PRTGInheritanceBreaks.ps1` with console output, grouped summary, and optional CSV export
- All files encoded as **UTF-8 with BOM** for Windows PowerShell 5.1 compatibility
