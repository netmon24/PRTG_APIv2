#requires -Version 5.1
<#
    PRTG.PowerShell.psm1
    ---------------------
    Modul-Loader. Lädt zur Laufzeit alle Skriptdateien aus den Unterordnern
    'Private' (interne Hilfsfunktionen, nicht exportiert) und 'Public'
    (Cmdlets, die dem Anwender zur Verfügung gestellt werden).

    Dieses Muster (dot-sourcing einzelner .ps1-Dateien statt eines einzigen
    großen .psm1) erleichtert Wartung und Versionierung: jedes Cmdlet lebt in
    seiner eigenen Datei mit eigener Hilfe (Get-Help <Cmdletname> -Full).
#>

$moduleRoot = $PSScriptRoot

$privateFunctions = Get-ChildItem -Path (Join-Path $moduleRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
$publicFunctions  = Get-ChildItem -Path (Join-Path $moduleRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($file in @($privateFunctions + $publicFunctions)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Fehler beim Laden von '$($file.FullName)': $($_.Exception.Message)"
        throw
    }
}

# Nur die Public-Cmdlets nach außen sichtbar machen. Die genaue Liste wird im
# Modul-Manifest (PRTG.PowerShell.psd1 / FunctionsToExport) noch einmal
# explizit gepflegt, damit 'Import-Module -Force' und Tools wie
# Get-Command -Module konsistente Ergebnisse liefern.
Export-ModuleMember -Function $publicFunctions.BaseName -Alias *
