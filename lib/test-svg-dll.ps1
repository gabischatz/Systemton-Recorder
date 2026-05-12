<#
.SYNOPSIS
    Testet, ob Svg.dll geladen werden kann.
.DESCRIPTION
    Dieses Skript prüft, ob Svg.dll im selben Ordner existiert
    und versucht, sie einmalig zu laden.
.NOTES
    Das Skript muss im selben Ordner wie Svg.dll liegen (lib-Ordner).
    Ausführung:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-svg-dll.ps1
#>

$ErrorActionPreference = 'Stop'

# Das Skript liegt im lib-Ordner, genau wie die Svg.dll
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dllPath = Join-Path $scriptDir 'Svg.dll'

Write-Host "Suche nach: $dllPath" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $dllPath)) {
    Write-Host "FEHLER: Svg.dll nicht gefunden unter:" -ForegroundColor Red
    Write-Host "        $dllPath" -ForegroundColor Red
    Write-Host "`nBitte führen Sie zuerst SvgDll-laden.bat aus." -ForegroundColor Yellow
    exit 1
}

try {
    Add-Type -Path $dllPath -ErrorAction Stop

    Write-Host "ERFOLG: Svg.dll wurde geladen von:" -ForegroundColor Green
    Write-Host "        $dllPath" -ForegroundColor Green

    # Version ohne zweites Laden der Assembly ermitteln.
    try {
        $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($dllPath)
        $version = $assemblyName.Version
        Write-Host "Version: $version" -ForegroundColor Gray
    } catch {
        # Version konnte nicht ermittelt werden (nicht kritisch)
    }

    exit 0
}
catch {
    Write-Host "FEHLER: Svg.dll konnte nicht geladen werden:" -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
