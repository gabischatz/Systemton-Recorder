@echo off
setlocal

rem *******************************************************************
rem Systemton Recorder BAT-Starter v1.1.0
rem
rem Variante B:
rem   - Startet den Recorder und schließt das Konsolenfenster sofort.
rem   - Die PowerShell-Konsole wird versteckt gestartet.
rem   - Die GUI bleibt sichtbar.
rem   - Da diese BAT sofort beendet wird, kann sie den späteren ExitCode
rem     der GUI nicht mehr auswerten.
rem *******************************************************************

set "PS1=%USERPROFILE%\MP3\SystemtonRecorderGUI.ps1"
set "LOG=%TEMP%\mp3_last_run.log"

if not exist "%PS1%" (
  echo PS1 nicht gefunden: "%PS1%" > "%LOG%"
  start "" notepad "%LOG%"
  exit /b 3
)

start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%" -LauncherKind "BAT" -LauncherLogPath "%LOG%"

exit /b 0
