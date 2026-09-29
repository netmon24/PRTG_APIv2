@{
    RootModule        = 'PRTG.PowerShell.psm1'
    ModuleVersion      = '1.1.0'
    GUID               = '7a3d2e1c-4f6b-4a8e-9c2d-1b5e7f9a3c6d'
    Author             = 'Arne Brucker'
    CompanyName        = 'netmon24 GmbH & Co. KG'
    Copyright          = '(c) 2026 netmon24 GmbH & Co. KG'
    Description        = 'PowerShell-Modul zur Verwaltung von PRTG Network Monitor ueber die offizielle PRTG API v2 (REST/OpenAPI). Bietet Cmdlets zum Lesen (Get-), Erstellen (New-), Aendern (Set-), Loeschen (Remove-) sowie Pausieren/Fortsetzen (Suspend-/Resume-) von Probes, Gruppen, Geraeten, Sensoren und Kanaelen, inklusive Authentifizierung per API-Key oder Benutzername/Passwort.'
    PowerShellVersion  = '5.1'

    FunctionsToExport = @(
        'Connect-PRTGServer',
        'Disconnect-PRTGServer',
        'Get-PRTGChannel',
        'Get-PRTGDevice',
        'Get-PRTGGroup',
        'Get-PRTGInheritanceBreak',
        'Get-PRTGObject',
        'Get-PRTGObjectCount',
        'Get-PRTGProbe',
        'Get-PRTGSensor',
        'Get-PRTGSensorStatusSummary',
        'Get-PRTGTimeseries',
        'Move-PRTGObject',
        'New-PRTGDevice',
        'New-PRTGGroup',
        'Remove-PRTGDevice',
        'Remove-PRTGGroup',
        'Remove-PRTGProbe',
        'Resume-PRTGDevice',
        'Resume-PRTGGroup',
        'Resume-PRTGProbe',
        'Set-PRTGDevice',
        'Set-PRTGGroup',
        'Start-PRTGScan',
        'Suspend-PRTGDevice',
        'Suspend-PRTGGroup',
        'Suspend-PRTGProbe',
        'Test-PRTGServerHealth'
    )

    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @(
        'Pause-PRTGDevice',
        'Pause-PRTGGroup',
        'Pause-PRTGProbe'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PRTG', 'Monitoring', 'Paessler', 'API', 'REST', 'NetworkMonitoring')
            ProjectUri   = 'https://github.com/netmon24/PRTG_APIv2'
            ReleaseNotes = '1.1.0: Behebt zwei Fehler, die Schreibzugriffe unter Windows PowerShell 5.1 unbrauchbar machten - der Zertifikats-Bypass war nicht zuweisbar, und Umlaute im Request-Body wurden zerstoert. Aendert ausserdem den Standardport von 443 auf 1616 (Breaking Change) - die API v2 liegt auf dem Application Server. Siehe CHANGELOG.md.'
        }
    }
}
