Systemton Recorder v1.62.0

Neu:
- Die Icons der unteren Aktionsleiste werden ueber recorder-config.json konfiguriert.
- Beim ersten Start ergaenzt die App fehlende Standardwerte automatisch.
- Bestehende recorder-config.json muss nicht geloescht werden.

Neue Konfigurationsfelder:

"iconDir": "assets",
"actionIcons": {
  "openFile": {
    "name": "Zu Datei",
    "file": "icon_folder.png",
    "shortcut": "Strg+Q"
  },
  "delete": {
    "name": "Loeschen",
    "file": "icon_garbage.png",
    "shortcut": "Strg+L"
  },
  "rename": {
    "name": "Umbenennen",
    "file": "icon_rename.png",
    "shortcut": "Strg+U"
  },
  "play": {
    "name": "Spielen",
    "file": "icon_play.png",
    "shortcut": "Strg+P"
  }
}

Hinweis:
- iconDir kann relativ zum Programmordner sein, z.B. "assets".
- iconDir kann auch absolut sein, z.B. "D:\\MeineIcons".
- file kann PNG oder ICO sein.
- name erscheint im Hovertext und kann fuer andere Sprachen angepasst werden.

Version 1.63.0:
- Alle sichtbaren UI-Symbole sind ueber recorder-config.json konfigurierbar.
- Start/Pause hat getrennte Icons: start, pause, resume.
- SVG-Dateien liegen als Quelle in assets; die GUI nutzt PNG/ICO fuer die Anzeige.

Version 1.64.0:
- Standard-SVGs sind zusätzlich direkt im Skript eingebettet.
- Fehlen SVG-Dateien im assets-Ordner, werden sie aus dem Skript wiederhergestellt.
- Fehlen PNG-Dateien und liegt lib\Svg.dll vor, werden PNGs automatisch aus den eingebetteten SVGs erzeugt.
- Ohne Svg.dll bleibt die App stabil und nutzt die mitgelieferten PNG/ICO-Dateien.

Version 1.65.0:
- Defekten Zeilenumbruch beim Mikrofon-Icon korrigiert.

Version 1.66.0:
- Umbenennen-Dialog deaktiviert TopMost vorübergehend.
- Nach dem Umbenennen wird TopMost wieder aktiviert, wenn die Option aktiv ist.
- SpeedCommander-Starter v1.2.0: START_MODE=2 sichtbar, aber ohne -NoExit und ohne Log-Anzeige bei Erfolg.

Version 1.67.0:
- Interne WAV-Wiedergabe eingebaut.
- Der Stopp-Button beendet auch die interne Wiedergabe.
- Externe Programme werden beim Abspielen von WAV-Dateien nicht mehr gestartet.

Version 1.68.0:
- Interne Wiedergabe nutzt WMPlayer.OCX statt System.Media.SoundPlayer.
- Damit werden auch nicht-PCM-WAV-Dateien direkt im Recorder abgespielt.
- Es wird kein externes Programmfenster geöffnet.
- Stopp beendet die interne Wiedergabe.

Version 1.69.0:
- Interne Wiedergabe nutzt System.Windows.Media.MediaPlayer statt WMPlayer.OCX.
- WAV/MP3/M4A werden über die Windows-Media-Engine versucht.
- Es wird kein externes Programmfenster geöffnet.
- Stop beendet weiterhin Aufnahme oder Wiedergabe.

Version 1.70.0:
- Visualizer im Leerlauf beruhigt: aktive Quelle zeigt nur eine Grundlinie.
- Aufnahme-Visualizer nutzt eine Rauschschwelle gegen Zittern ohne Ton.
- SpeedCommander wird mit dem Pfad der markierten Datei aufgerufen.
- Starter v1.3.0 kann optional SPEEDCOMMANDER_EXE an die PS1 uebergeben.

Version 1.71.0:
- Visualizer im Leerlauf deutlich hoeher, aber statisch ohne Zittern.
- Wiedergabe nutzt WinMM/MCI statt WPF MediaPlayer.
- Dadurch soll die GUI beim Abspielen nicht mehr springen oder kleiner skalieren.

Version 1.72.0:
- Vorbereitung/Leerlauf zeigt nur eine ruhige grüne Grundlinie.
- Bei Aufnahme wird ein segmentierter Equalizer mit Grün/Gelb/Rot gezeichnet.
- Keine hohen Balken mehr, solange nicht aufgenommen wird.

Version 1.73.0:
- MCI close vor dem Öffnen wird still ignoriert.
- Dadurch scheitert Play nicht mehr daran, dass beim ersten Abspielen noch kein Gerät geöffnet war.
- MCI open nutzt type mpegvideo.

Version 1.75.0:
- Basiert bewusst auf dem stabilen Stand 1.73.0.
- Beim Zurückkehren zum Recorder wird der Aufnahmeordner automatisch abgeglichen.
- Die Dateiliste übernimmt Änderungen aus SpeedCommander/Explorer.
- Die zuvor markierte Aufnahme wird nach Möglichkeit wieder markiert.

Version 1.76.0:
- Stopp setzt die Zeitanzeige nach Aufnahme wieder auf 00:00:00.
- Stopp setzt die Zeitanzeige auch nach interner Wiedergabe zurück.

Version 1.77.0:
- Der Recorder unterscheidet jetzt explizit zwischen SpeedCommander-Makro und BAT/normalem Start.
- SpeedCommander-Makro uebergibt LauncherKind=SpeedCommander, SC-Pfad, SC-Version und Fenster-/Auswahldaten.
- Bei SpeedCommander-Start wird 'Zu Datei' mit SpeedCommander.exe und Dateipfad ausgefuehrt.
- Bei BAT/normalem Start wird 'Zu Datei' bewusst im Explorer angezeigt.
- Neues Makro: SpeedCommanderMP3Starter.v1.4.0.scmac
- Neue BAT: SystemtonRecorderGUI-starten.bat

Version 1.78.0:
- Zwei BAT-Starter ergänzt:
  1) SystemtonRecorderGUI-starten-warten.bat
     - Konsole bleibt offen, bis die GUI beendet wurde.
     - Fehlercode kann ausgewertet werden.
     - Log wird bei Fehler angezeigt.
  2) SystemtonRecorderGUI-starten-sofort-schliessen.bat
     - Konsole schließt sofort nach dem Start.
     - PowerShell-Konsole wird versteckt gestartet.
     - GUI bleibt sichtbar.
     - Spätere ExitCodes der GUI können von dieser BAT nicht mehr ausgewertet werden.

Version 1.78.1:
- AppVersion in SystemtonRecorderGUI.ps1 korrigiert.
- recorder-config.json auf neues icons-Format bereinigt; actionIcons entfernt.
- SpeedCommanderMP3Starter.scmac: WScript.Quit durch Exit Sub ersetzt.
- SpeedCommanderMP3Starter.scmac: doppelte ExpandEnvironmentStrings-Auswertung entfernt.
- lib/test-svg-dll.ps1: doppelte Assembly-Ladung entfernt.
