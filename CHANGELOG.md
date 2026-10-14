# Changelog

All notable changes to this project will be documented in this file.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
This project uses [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **`Scripts/Import-PRTGStructureFromExcel.ps1`** - rebuilds a PRTG tree in a
  target system from a sensor export: groups and devices through this module's
  cmdlets, and optionally the sensors themselves via `-CreateSensors`.
  Idempotent, supports `-WhatIf`, logs to CSV with `-ExportCsv`. It carries the
  lessons that cost real time to learn - port 1616 rather than 443, the
  certificate bypass having to be a compiled delegate, text values in API
  filters needing double quotes, names containing `( ) [ ] &` being
  unfilterable, newly created objects not being queryable immediately, and
  sensor types having to be matched by display name because kind `ping` and
  `paessler.icmp.ping_sensor` coexist and show as `Ping` and `Ping v2`.
- `-ResolveAttempts` and `-ResolveDelayMs` on the import script control how long
  it waits for a freshly created object to become queryable. The previous fixed
  window of 8 attempts at 750 ms - about 6 seconds - proved far too short on a
  real server, where 5 of 8 groups were reported as created but not queryable
  and all their devices were skipped as a consequence. The default is now 15
  attempts at 1000 ms, and the warning names the actual window instead of a
  hard-coded "6 s".
- `examples/PRTG-Export-Demo.xlsx` - example workbook, 32 rows across 3 groups
  and 8 devices. Addresses come from the RFC 5737 documentation ranges, so they
  cannot collide with anyone's real network. 13 of the 32 rows carry sensor names
  with parameters (`SNMP Traffic GigabitEthernet0/0`, `Disk Free C:\`,
  `Port 1433`), because that is what a real export looks like and because those
  are the rows a migration cannot replay. A second worksheet, `Hinweise`,
  explains the data for whoever opens the file.
- The import script now says what `-SensorKindFilter` left out ("18 distinct
  sensor names in the sheet, 9 of them selected") and, for the names it cannot
  resolve, whether that is because they carry parameters. Those are reported
  once, grouped by type with examples ("SNMP Traffic 6x Dialer1, eth0,
  GigabitEthernet0/0, ..."), land in the summary as `Sensor, NeedsParameters`
  and in the `-ExportCsv` log, so they can be worked off as a list. A real
  export brings dozens of them, and a wall of identical warnings gets ignored.
- `-ApiToken` on the import script, so a run needs no console. `-CreateSensors`
  always prompted for the key, which made the sensor step impossible to run
  from a scheduled task or a test harness.
- README section **Migrating from an existing PRTG**: expected worksheet
  columns, a typical run, why PRTG cannot be asked to discover the sensors
  itself through API v2, and a prominent warning that sensor creation depends on
  experimental API endpoints.
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
- **The import script claimed auto-discovery had been set up when the server had
  refused it.** `basic.discoverytype` is answered with `400 Bad Request` on every
  device POST — the setting exists in the classic interface, not in API v2. The
  script sent the field by default, logged a warning per device, retried without
  it, and then closed with "New devices were created with
  discoverytype='Detailed', so PRTG discovers sensors on its own". On a 55-device
  import that produced 55 identical 400s and the expectation of roughly 925
  sensors appearing by themselves; none ever did. The field is now left out by
  default (`-SensorDiscoveryMode Manual`), a single rejection stops any further
  attempt for the rest of the run, and the closing note reports what the server
  actually accepted rather than what was intended.
- Another instance of the comment-based help trap, from the other direction: a
  help block line beginning with `.xlsx` is read as a help keyword and makes
  PowerShell discard the **entire** block, silently. Found because `Get-Help`
  returned nothing for the new script; reworded so no line starts with a dot.
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
- **`404 Not Found` was the answer to three different mistakes when creating a
  group or device**, and it read like a missing endpoint in all three: the parent
  id does not exist, it points at another kind of object than the chosen
  parameter implies, or the server has no endpoint for that parent/child
  combination. Passing a group id as `-ParentProbeId` cost an afternoon on a
  production migration. `New-PRTGGroup` and `New-PRTGDevice` now look the object
  up after a 404 and report which of the three it is - "Objekt 52735 ist eine
  Gruppe ('...'), erwartet wurde eine Probe. Verwenden Sie -ParentGroupId 52735."
  Any status other than 404 is passed through untouched.
- `New-PRTGDevice -ParentProbeId` built the path
  `/experimental/probes/{id}/device`, which the API v2 specification does not
  define - devices exist below groups only. The call now explains that and points
  at `New-PRTGGroup -ParentProbeId` as the first step instead of reporting a bare
  404. Listed under Known Limitations.
- `Invoke-PRTGRestMethod` carries the HTTP status code on the exception
  (`$_.Exception.Data['StatusCode']`, plus path and method) instead of only
  writing it into the message text, so callers can react to a specific failure
  without parsing German error strings.

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
- `-SkipSensorDiscovery` on the import script. It did the same thing as
  `-SensorDiscoveryMode Manual`, which is now the default, so every call needed
  to get two switches right to express one intention.
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
