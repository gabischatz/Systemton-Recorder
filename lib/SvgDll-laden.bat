@echo off
setlocal EnableExtensions

rem *******************************************************************
rem Svg.dll Downloader v1.0.1
rem
rem Zweck:
rem   - Laedt das NuGet-Paket "Svg" herunter.
rem   - Entpackt daraus Svg.dll.
rem   - Kopiert Svg.dll in denselben Ordner wie dieses Batch.
rem
rem Nutzung:
rem   - Diese BAT liegt im lib-Ordner des Recorder-Ordners.
rem   - Dann ausfuehren.
rem   - Danach liegt die Datei hier:
rem       lib\Svg.dll (gleicher Ordner wie die BAT)
rem
rem Hinweis:
rem   - Internetverbindung erforderlich.
rem   - Es wird keine Datei ersetzt, ohne vorher eine Sicherung anzulegen.
rem *******************************************************************

set "BASE_DIR=%~dp0"
set "TMP_DIR=%TEMP%\svg_dll_download_%RANDOM%%RANDOM%"
set "LOG=%BASE_DIR%svg-dll-download.log"

echo ============================================================ > "%LOG%"
echo Svg.dll Downloader v1.0.1 >> "%LOG%"
echo Zeit: %DATE% %TIME% >> "%LOG%"
echo Zielordner: %BASE_DIR% >> "%LOG%"
echo ============================================================ >> "%LOG%"
echo. >> "%LOG%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$targetDir = '%BASE_DIR%';" ^
  "$tmp = '%TMP_DIR%';" ^
  "$log = '%LOG%';" ^
  "function Log($t){ Add-Content -LiteralPath $log -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $t) -Encoding UTF8 }" ^
  "try {" ^
  "  Log 'Starte Download von Svg.dll';" ^
  "  New-Item -ItemType Directory -Force -Path $tmp | Out-Null;" ^
  "  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
  "  $indexUrl = 'https://api.nuget.org/v3-flatcontainer/svg/index.json';" ^
  "  Log ('Lese Paketindex: ' + $indexUrl);" ^
  "  $idx = Invoke-RestMethod -Uri $indexUrl -UseBasicParsing;" ^
  "  $version = $idx.versions[-1];" ^
  "  if ([string]::IsNullOrWhiteSpace($version)) { throw 'Keine Svg-Version gefunden.' }" ^
  "  Log ('Gefundene Version: ' + $version);" ^
  "  $pkgUrl = 'https://api.nuget.org/v3-flatcontainer/svg/' + $version + '/svg.' + $version + '.nupkg';" ^
  "  $pkg = Join-Path $tmp ('svg.' + $version + '.nupkg');" ^
  "  Log ('Lade Paket: ' + $pkgUrl);" ^
  "  Invoke-WebRequest -Uri $pkgUrl -OutFile $pkg -UseBasicParsing;" ^
  "  $zip = Join-Path $tmp ('svg.' + $version + '.zip');" ^
  "  Copy-Item -LiteralPath $pkg -Destination $zip -Force;" ^
  "  $extract = Join-Path $tmp 'extract';" ^
  "  Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force;" ^
  "  $dlls = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'Svg.dll' | Sort-Object FullName;" ^
  "  if (-not $dlls -or $dlls.Count -lt 1) { throw 'Svg.dll wurde im Paket nicht gefunden.' }" ^
  "  $preferred = $dlls | Where-Object { $_.FullName -match '\\lib\\net4' } | Select-Object -First 1;" ^
  "  if (-not $preferred) { $preferred = $dlls | Select-Object -First 1 }" ^
  "  $target = Join-Path $targetDir 'Svg.dll';" ^
  "  if (Test-Path -LiteralPath $target) {" ^
  "    $backup = Join-Path $targetDir ('Svg.dll.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'));" ^
  "    Copy-Item -LiteralPath $target -Destination $backup -Force;" ^
  "    Log ('Bestehende Svg.dll gesichert als: ' + $backup);" ^
  "  }" ^
  "  Copy-Item -LiteralPath $preferred.FullName -Destination $target -Force;" ^
  "  Log ('Svg.dll gespeichert: ' + $target);" ^
  "  Log 'Fertig.';" ^
  "  Write-Host 'Svg.dll wurde erfolgreich geladen.' -ForegroundColor Green;" ^
  "  Write-Host ('Ziel: ' + $target) -ForegroundColor Green;" ^
  "  exit 0;" ^
  "} catch {" ^
  "  Log ('FEHLER: ' + $_.Exception.Message);" ^
  "  Write-Host ('FEHLER: ' + $_.Exception.Message) -ForegroundColor Red;" ^
  "  exit 1;" ^
  "} finally {" ^
  "  try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force } } catch {}" ^
  "}"

set "EC=%ERRORLEVEL%"

if not "%EC%"=="0" (
  echo.
  echo Fehler beim Laden von Svg.dll.
  echo Logdatei wird geoeffnet:
  echo %LOG%
  notepad "%LOG%"
  exit /b %EC%
)

echo.
echo Svg.dll wurde erfolgreich geladen.
echo Ziel: %BASE_DIR%Svg.dll
echo Logdatei: %LOG%
exit /b 0