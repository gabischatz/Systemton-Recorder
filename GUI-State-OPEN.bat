@echo off
setlocal

rem *******************************************************************
rem Systemton Recorder BAT-Starter v1.1.0
rem
rem Variante A:
rem   - Konsole bleibt offen, solange der Recorder läuft.
rem   - ExitCode kann ausgewertet werden.
rem   - Log wird bei Fehler automatisch angezeigt.
rem *******************************************************************

set "PS1=%USERPROFILE%\MP3\SystemtonRecorderGUI.ps1"
set "LOG=%TEMP%\mp3_last_run.log"

if not exist "%PS1%" (
  echo PS1 nicht gefunden: "%PS1%" > "%LOG%"
  notepad "%LOG%"
  exit /b 3
)

powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -LauncherKind "BAT" -LauncherLogPath "%LOG%"
set "EC=%ERRORLEVEL%"

if not "%EC%"=="0" (
  echo PowerShell wurde beendet mit ExitCode %EC%.>> "%LOG%"
  notepad "%LOG%"
)

exit /b %EC%
