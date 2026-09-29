# PRTG.PowerShell

PowerShell module for the **PRTG API v2** (Paessler PRTG Network Monitor).

This folder is the module itself. Copy its **contents** into a version
subfolder named exactly after `ModuleVersion` in `PRTG.PowerShell.psd1`:

```
...\Modules\PRTG.PowerShell\<ModuleVersion>\PRTG.PowerShell.psd1
```

**Full documentation — installation, updating, troubleshooting and the
complete cmdlet reference — is in the [README at the repository root](../README.md).**

Quick check after installing:

```powershell
Import-Module PRTG.PowerShell -Force
Get-Command -Module PRTG.PowerShell
Get-Help Connect-PRTGServer -Full
```
