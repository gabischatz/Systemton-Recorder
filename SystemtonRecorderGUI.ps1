<#
Projekt: SystemtonRecorder
Version 1.78.1:
#>

param(
    [string]$ActivePath = "",
    [string]$ActiveSelection = "",
    [string]$ActiveFocused = "",
    [string]$SpeedCommanderExe = "",
    [string]$LauncherKind = "BAT",
    [string]$LauncherLogPath = "",
    [string]$SpeedCommanderVersion = "",
    [string]$InactivePath = "",
    [string]$InactiveSelection = "",
    [string]$InactiveFocused = ""
)

# GUI-Laufzeit bewusst ohne StrictMode, damit Nebenereignisse die Oberfläche nicht hart beenden.
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Windows: eigenes AppUserModelID setzen, damit die Taskleiste eher das Recorder-Icon
# statt das allgemeine PowerShell-Icon verwendet.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RecorderTaskbarIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void SetCurrentProcessExplicitAppUserModelID(string AppID);
}
"@ -ErrorAction SilentlyContinue | Out-Null
    [RecorderTaskbarIcon]::SetCurrentProcessExplicitAppUserModelID('Lutz.SystemtonRecorder.Native')
} catch { }
Add-Type -AssemblyName Microsoft.VisualBasic

try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeProcessControl {
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtSuspendProcess(IntPtr processHandle);
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern int NtResumeProcess(IntPtr processHandle);
}
"@
} catch {}

try {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @"
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Drawing.Drawing2D;

public class RecorderToolbarButton : Control
{
    private Image _image;
    private bool _mouseOver = false;
    private bool _mouseDown = false;

    public Color NormalBackColor { get; set; }
    public Color HoverBackColor { get; set; }
    public Color DownBackColor { get; set; }
    public Image Image
    {
        get { return _image; }
        set { _image = value; Invalidate(); }
    }

    public RecorderToolbarButton()
    {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);

        TabStop = false;
        NormalBackColor = Color.FromArgb(224,232,239);
        HoverBackColor = Color.FromArgb(204,222,238);
        DownBackColor = Color.FromArgb(175,205,230);
        BackColor = NormalBackColor;
        ForeColor = Color.Black;
        Cursor = Cursors.Hand;
    }

    protected override bool ShowFocusCues
    {
        get { return false; }
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        _mouseOver = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        _mouseOver = false;
        _mouseDown = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            _mouseDown = true;
            Invalidate();
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        _mouseDown = false;
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnEnabledChanged(EventArgs e)
    {
        Invalidate();
        base.OnEnabledChanged(e);
    }

    protected override void OnBackColorChanged(EventArgs e)
    {
        NormalBackColor = BackColor;
        Invalidate();
        base.OnBackColorChanged(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;

        Color bg = NormalBackColor;
        if (!Enabled)
        {
            bg = Color.FromArgb(224,232,239);
        }
        else if (_mouseDown)
        {
            bg = DownBackColor;
        }
        else if (_mouseOver)
        {
            bg = HoverBackColor;
        }

        using (SolidBrush b = new SolidBrush(bg))
        {
            g.FillRectangle(b, ClientRectangle);
        }

        int iconSize = 18;
        int iconX = 12;
        int iconY = (Height - iconSize) / 2;
        int textX = 44;

        if (_image != null)
        {
            // Das Bild wird bewusst quadratisch gezeichnet.
            // Ältere Versionen haben die transparente Icon-Leinwand auf Buttonbreite gestaucht,
            // dadurch wirkten die Symbole in der Buttonbar zusammengequetscht.
            Rectangle dest = new Rectangle(iconX, iconY, iconSize, iconSize);
            Rectangle src = new Rectangle(0, 0, Math.Min(_image.Width, _image.Height), Math.Min(_image.Width, _image.Height));
            if (src.Width < 1 || src.Height < 1) src = new Rectangle(0, 0, _image.Width, _image.Height);
            if (Enabled)
            {
                g.DrawImage(_image, dest, src, GraphicsUnit.Pixel);
            }
            else
            {
                ControlPaint.DrawImageDisabled(g, _image, iconX, iconY, bg);
            }
            textX = iconX + iconSize + 16;
        }

        Rectangle textRect = new Rectangle(textX, 0, Width - textX - 8, Height);
        TextFormatFlags flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
        Color textColor = Enabled ? ForeColor : SystemColors.GrayText;
        TextRenderer.DrawText(g, Text, Font, textRect, textColor, flags);
    }
}
"@
} catch {}

$script:AppVersion = 'v1.78.1'
$script:BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:AssetsDir = Join-Path $script:BaseDir 'assets'
$script:ConfigPath = Join-Path $script:BaseDir 'recorder-config.json'
$script:IndexPath  = Join-Path $script:BaseDir 'recordings-index.json'
$script:BinDir     = Join-Path $script:BaseDir 'bin'
$script:LogPath    = Join-Path $script:BaseDir 'recorder-last-run.log'

$script:Config = [ordered]@{
    ffmpegPath = ''
    outputDir = (Join-Path ([Environment]::GetFolderPath('MyMusic')) 'Systemton-Aufnahmen')
    source = 'System-Sound'
    microphoneDevice = 'Standardmikrofon'
    format = 'WAV'
    quality = 'Normal'
    autoSave = $true
    showFileAfterRecording = $true
    debugMode = $false
    alwaysOnTop = $false
    windowLeft = $null
    windowBottom = $null
    windowWidth = 560
    speedCommanderExe = ''
    webUrl = 'https://ttsopenai.com/'
    iconDir = 'assets'
    icons = [ordered]@{
        systemSound = [ordered]@{
            name = 'System-Sound'
            file = 'icon_system_sound.png'
            shortcut = 'Alt+S'
        }
        microphone = [ordered]@{
            name = 'Mikrofon'
            file = 'icon_microphone.png'
            shortcut = 'Alt+M'
        }
        start = [ordered]@{
            name = 'Start'
            file = 'icon_start.png'
            shortcut = 'Alt+S'
        }
        pause = [ordered]@{
            name = 'Pause'
            file = 'icon_pause.png'
            shortcut = 'Leertaste'
        }
        resume = [ordered]@{
            name = 'Weiter'
            file = 'icon_resume.png'
            shortcut = 'Leertaste'
        }
        stop = [ordered]@{
            name = 'Stopp'
            file = 'icon_stop.png'
            shortcut = 'Esc'
        }
        files = [ordered]@{
            name = 'Dateien'
            file = 'icon_files.png'
            shortcut = 'Strg+D'
        }
        settings = [ordered]@{
            name = 'Einstellungen'
            file = 'icon_settings.png'
            shortcut = 'Strg+E'
        }
        openFile = [ordered]@{
            name = 'Zu Datei'
            file = 'SC.ico'
            shortcut = 'Strg+Q'
        }
        delete = [ordered]@{
            name = 'Loeschen'
            file = 'icon_delete.png'
            shortcut = 'Strg+L'
        }
        rename = [ordered]@{
            name = 'Umbenennen'
            file = 'icon_rename.png'
            shortcut = 'Strg+U'
        }
        play = [ordered]@{
            name = 'Spielen'
            file = 'icon_play.png'
            shortcut = 'Strg+P'
        }
        folder = [ordered]@{
            name = 'Ordner waehlen'
            file = 'icon_folder.png'
            shortcut = 'Strg+O'
        }
        web = [ordered]@{
            name = 'Webseite oeffnen'
            file = 'icon_web.png'
            shortcut = 'Strg+Alt+Q'
        }
    }
    actionIcons = [ordered]@{
        openFile = [ordered]@{
            name = 'Zu Datei'
            file = 'SC.ico'
            shortcut = 'Strg+Q'
        }
        delete = [ordered]@{
            name = 'Loeschen'
            file = 'icon_delete.png'
            shortcut = 'Strg+L'
        }
        rename = [ordered]@{
            name = 'Umbenennen'
            file = 'icon_rename.png'
            shortcut = 'Strg+U'
        }
        play = [ordered]@{
            name = 'Spielen'
            file = 'icon_play.png'
            shortcut = 'Strg+P'
        }
    }
}

# Eingebettete SVG-Quellen fuer Standard-Icons.
# Die GUI zeigt weiterhin PNG/ICO an; diese SVGs dienen als Quelle fuer Wiederherstellung/Cache.
$script:EmbeddedSvgIcons = @{
    systemSound = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#8899A6" d="M2 10s-2 0-2 2v12c0 2 2 2 2 2h6l8 8s1 1 2 1h1s1 0 1-1V2s0-1-1-1h-1c-1 0-2 1-2 1l-8 8H2z"/><path fill="#CCD6DD" d="M8 26l8 8s1 1 2 1h1s1 0 1-1V2s0-1-1-1h-1c-1 0-2 1-2 1l-8 8v16z"/><path fill="#8899A6" d="M29 32.019c-.267 0-.533-.113-.72-.332-.339-.398-.292-.995.105-1.334 3.603-3.071 5.668-7.551 5.668-12.29s-2.066-9.219-5.669-12.29c-.397-.339-.444-.937-.105-1.334.339-.399.935-.444 1.334-.106 4.024 3.431 6.333 8.436 6.333 13.73 0 5.294-2.309 10.299-6.332 13.729-.179.152-.396.227-.614.227z"/><path fill="#8899A6" d="M26.27 28.959c-.269 0-.533-.115-.717-.338-.327-.396-.271-.98.125-1.307 2.792-2.304 4.394-5.699 4.394-9.315 0-3.573-1.571-6.943-4.311-9.245-.392-.33-.443-.916-.113-1.308.33-.394.915-.443 1.309-.114 3.16 2.656 4.973 6.543 4.973 10.667 0 4.172-1.848 8.089-5.069 10.746-.174.145-.383.214-.591.214z"/><path fill="#8899A6" d="M23.709 25.959c-.289 0-.576-.124-.774-.365-.351-.427-.289-1.057.138-1.407C24.934 22.658 26 20.403 26 18c0-2.435-1.089-4.708-2.988-6.236-.431-.346-.498-.976-.152-1.406.348-.429.976-.499 1.406-.152C26.639 12.116 28 14.957 28 18c0 3.004-1.333 5.822-3.657 7.731-.186.154-.411.228-.634.228z"/></svg>
'@
    microphone = @'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect x="48" y="14" width="32" height="58" rx="14" fill="#d8d8d8" stroke="#202020" stroke-width="5"/>
  <path d="M36 56v10c0 16 12 28 28 28s28-12 28-28V56" fill="none" stroke="#202020" stroke-width="7" stroke-linecap="round"/>
  <path d="M64 94v18M48 112h32" fill="none" stroke="#202020" stroke-width="7" stroke-linecap="round"/>
  <rect x="54" y="74" width="20" height="10" fill="#555"/>
</svg>
'@
    start = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#3B88C3" d="M36 32c0 2.209-1.791 4-4 4H4c-2.209 0-4-1.791-4-4V4c0-2.209 1.791-4 4-4h28c2.209 0 4 1.791 4 4v28z"/><path fill="#FFF" d="M6 7l13 11L6 29zm20 0h4v22h-4zm-7 0h4v22h-4z"/></svg>
'@
    pause = @'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect x="8" y="8" width="112" height="112" rx="12" fill="#3b8fd0"/>
  <rect x="38" y="30" width="16" height="68" rx="3" fill="#ffffff"/>
  <rect x="74" y="30" width="16" height="68" rx="3" fill="#ffffff"/>
</svg>
'@
    resume = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#3B88C3" d="M36 32c0 2.209-1.791 4-4 4H4c-2.209 0-4-1.791-4-4V4c0-2.209 1.791-4 4-4h28c2.209 0 4 1.791 4 4v28z"/><path fill="#FFF" d="M6 7l13 11L6 29zm20 0h4v22h-4zm-7 0h4v22h-4z"/></svg>
'@
    stop = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#3B88C3" d="M36 32c0 2.209-1.791 4-4 4H4c-2.209 0-4-1.791-4-4V4c0-2.209 1.791-4 4-4h28c2.209 0 4 1.791 4 4v28z"/><path fill="#FFF" d="M7 7h22v22H7z"/></svg>
'@
    files = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#E1E8ED" d="M32.415 9.586l-9-9C23.054.225 22.553 0 22 0c-1.104 0-1.999.896-2 2 0 .552.224 1.053.586 1.415l-3.859 3.859 9 9 3.859-3.859c.362.361.862.585 1.414.585 1.104 0 2.001-.896 2-2 0-.552-.224-1.052-.585-1.414z"/><path fill="#CCD6DD" d="M22 0H7C4.791 0 3 1.791 3 4v28c0 2.209 1.791 4 4 4h22c2.209 0 4-1.791 4-4V11h-9c-1 0-2-1-2-2V0z"/><path fill="#99AAB5" d="M22 0h-2v9c0 2.209 1.791 4 4 4h9v-2h-9c-1 0-2-1-2-2V0zm-5 8c0 .552-.448 1-1 1H8c-.552 0-1-.448-1-1s.448-1 1-1h8c.552 0 1 .448 1 1zm0 4c0 .552-.448 1-1 1H8c-.552 0-1-.448-1-1s.448-1 1-1h8c.552 0 1 .448 1 1zm12 4c0 .552-.447 1-1 1H8c-.552 0-1-.448-1-1s.448-1 1-1h20c.553 0 1 .448 1 1zm0 4c0 .553-.447 1-1 1H8c-.552 0-1-.447-1-1 0-.553.448-1 1-1h20c.553 0 1 .447 1 1zm0 4c0 .553-.447 1-1 1H8c-.552 0-1-.447-1-1 0-.553.448-1 1-1h20c.553 0 1 .447 1 1zm0 4c0 .553-.447 1-1 1H8c-.552 0-1-.447-1-1 0-.553.448-1 1-1h20c.553 0 1 .447 1 1z"/></svg>
'@
    settings = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0  24 24" style="&#10;    fill: white;&#10;    stroke: blue;&#10;">
<path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" style="stroke: blue;fill: lightblue;"/><circle cx="12" cy="12" r="3"/>
</svg>
'@
    openFile = @'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <g transform="translate(1.4065934065934016 1.4065934065934016) scale(2.81 2.81)">
    <!-- Ordner-Hintergrund (gelb) -->
    <path d="M 73.538 35.162 l -52.548 1.952 c -1.739 0 -2.753 0.651 -3.232 2.323 L 6.85 76.754 c -0.451 1.586 -2.613 2.328 -4.117 2.328 h 0 C 1.23 79.082 0 77.852 0 76.349 l 0 -10.458 V 23.046 v -2.047 v -6.273 c 0 -2.103 1.705 -3.808 3.808 -3.808 h 27.056 c 1.01 0 1.978 0.401 2.692 1.115 l 7.85 7.85 c 0.714 0.714 1.683 1.115 2.692 1.115 H 69.73 c 2.103 0 3.808 1.705 3.808 3.808 v 1.301 L 73.538 35.162 z" fill="rgb(224,173,49)" stroke="none"/>
    
    <!-- Weisses Blatt im Ordner -->
    <path d="M 63.726 14.605 v 54.54 c 0 1.386 -1.124 2.51 -2.51 2.51 H 13.02 c -1.386 0 -2.51 -1.124 -2.51 -2.51 V 2.51 c 0 -1.386 1.124 -2.51 2.51 -2.51 H 49.12 C 51.554 6.059 56.533 10.874 63.726 14.605 z" fill="rgb(233,233,224)" stroke="none"/>
    <path d="M 63.726 14.605 H 51.407 c -1.263 0 -2.287 -1.024 -2.287 -2.287 V 0 L 63.726 14.605 z" fill="rgb(217,215,202)" stroke="none"/>
    
    <!-- Linien auf dem Blatt -->
    <path d="M 52.978 23.363 H 20.139 c -0.829 0 -1.5 -0.671 -1.5 -1.5 s 0.671 -1.5 1.5 -1.5 h 32.839 c 0.828 0 1.5 0.671 1.5 1.5 S 53.806 23.363 52.978 23.363 z" fill="rgb(217,215,202)" stroke="none"/>
    <path d="M 52.978 30.363 H 20.139 c -0.829 0 -1.5 -0.671 -1.5 -1.5 s 0.671 -1.5 1.5 -1.5 h 32.839 c 0.828 0 1.5 0.671 1.5 1.5 S 53.806 30.363 52.978 30.363 z" fill="rgb(217,215,202)" stroke="none"/>
    
    <!-- Unterer gelber Bereich (der Tab) -->
    <path d="M 2.733 79.082 L 2.733 79.082 c 1.503 0 2.282 -1.147 2.733 -2.733 l 10.996 -38.362 c 0.479 -1.672 2.008 -2.824 3.748 -2.824 h 67.379 c 1.609 0 2.765 1.546 2.311 3.09 L 79.004 75.279 c -0.492 1.751 -1.571 3.818 -3.803 3.803 H 2.733 z" fill="rgb(255,200,67)" stroke="none"/>
    
    <!-- Noten (aus zweitem Icon, unten im gelben Bereich) -->
    <g transform="translate(40, 38) scale(1.85)" fill="#000000">
      <path d="M10.653,8.76l8.145-1.321v11.043c0,0.914-0.681,1.644-1.744,1.913c-1.168,0.289-2.294-0.2-2.519-1.095c-0.224-0.897,0.541-1.858,1.708-2.15c0.527-0.13,1.047-0.103,1.481,0.05v-6.654l-5.969,1.092l-0.028,8.276c-0.005,0.783-0.713,1.554-1.729,1.805c-1.153,0.289-2.363-0.26-2.492-1.081c-0.221-0.886,0.534-1.837,1.691-2.127c0.52-0.13,1.029-0.104,1.456,0.046V8.76z" fill="#328c98"/>
      <path d="M7.591,12.81L7.62,2.581c0,0,2.228-0.119,4.407,3.298c0,0,0.006-1.764-1.669-3.055C7.087,0.54,7.096,0,7.096,0C6.472,0.073,6.408,0.547,6.408,0.547v10.771c-0.468-0.164-1.028-0.193-1.602-0.05c-1.27,0.314-2.1,1.363-1.857,2.338c0.143,0.901,1.471,1.506,2.74,1.187c1.115-0.278,1.894-1.12,1.9-1.983H7.591z" fill="coral"/>
      <path d="M13.515,6.2c0.388-0.097,0.659-0.39,0.661-0.69h0.001l0.01-3.559c0,0,0.775-0.041,1.533,1.148c0,0,0.001-0.614-0.582-1.062C14,1.242,14.004,1.054,14.004,1.054c-0.217,0.025-0.24,0.19-0.24,0.19v3.748c-0.162-0.058-0.356-0.068-0.556-0.019c-0.443,0.109-0.73,0.475-0.646,0.814C12.612,6.101,13.074,6.311,13.515,6.2z" fill="red"/>
      <path d="M17.355,6.209c0.27-0.067,0.458-0.272,0.46-0.481l0.007-2.479c0,0,0.54-0.029,1.068,0.799c0,0,0.001-0.428-0.404-0.74c-0.793-0.554-0.791-0.685-0.791-0.685c-0.151,0.018-0.167,0.133-0.167,0.133v2.611c-0.113-0.04-0.249-0.047-0.388-0.012c-0.308,0.076-0.509,0.33-0.45,0.566C16.724,6.14,17.046,6.287,17.355,6.209z" fill="blue"/>
    </g>
  </g>
</svg>
'@
    delete = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Generator: Adobe Illustrator 25.2.3, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
<svg version="1.1" id="Layer_4" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
	 viewBox="0 0 128 128" style="enable-background:new 0 0 128 128;" xml:space="preserve">
<g>
	<ellipse style="fill:#B9E4EA;" cx="63.94" cy="104.89" rx="35" ry="13.61"/>
	<path style="fill:#94D1E0;" d="M29.98,110.19c0-7.13,15.2-12.04,33.96-12.04s33.96,4.91,33.96,12.04s-15.2,13.53-33.96,13.53
		S29.98,117.32,29.98,110.19z"/>
	<linearGradient id="SVGID_1_" gradientUnits="userSpaceOnUse" x1="64.1107" y1="89.9664" x2="64.1107" y2="147.6283">
		<stop  offset="0" style="stop-color:#82AFC1"/>
		<stop  offset="1" style="stop-color:#2F7889"/>
	</linearGradient>
	<path style="fill:url(#SVGID_1_);" d="M108.51,32.83l-2.26,12.33l-6.61-6.61l3.44-3.44l-9.75,2.84l0.6,0.6l-8.09,8.09l-6.54-6.54
		l-9.63,0.82l-5.72,5.72l-6.2-6.2l-8.96-0.52l-6.72,6.72l-8.09-8.09l0.83-0.83l-9.36-1.98l2.81,2.81l-6.39,6.39L19.63,32.6
		l-4.56-2.58l14.51,80.37C30.7,118.02,45.29,124,64.05,124s33.08-5.98,34.51-13.61l14.6-80.45L108.51,32.83z M84.06,110.53
		l-6.32-6.32l8.09-8.09l8.09,8.09l0,0l-4.72,4.72C87.58,109.51,85.86,110.04,84.06,110.53z M39.21,109.46l-5.25-5.25l0,0l8.09-8.09
		l8.09,8.09l-6.51,6.51C42.09,110.34,40.61,109.91,39.21,109.46z M72.03,104.22l-8.09,8.09l-8.09-8.09l8.09-8.09L72.03,104.22z
		 M66.8,93.27l8.09-8.09l8.09,8.09l-8.09,8.09L66.8,93.27z M52.99,101.36l-8.09-8.09l8.09-8.09l8.09,8.09L52.99,101.36z
		 M52.99,107.07l6.13,6.13c-3.65-0.25-7.33-0.75-10.84-1.43L52.99,107.07z M68.76,113.2l6.13-6.13l4.58,4.58
		C75.99,112.39,72.36,112.94,68.76,113.2z M96.07,100.65l-7.38-7.38l8.09-8.09l1.8,1.8L96.07,100.65z M100.67,75.57l-3.89,3.89
		l-8.09-8.09l8.09-8.09l5.19,5.19L100.67,75.57z M93.92,82.32l-8.09,8.09l-8.09-8.09l8.09-8.09L93.92,82.32z M74.88,79.47
		l-8.09-8.09l8.09-8.09l8.09,8.09L74.88,79.47z M72.03,82.32l-8.09,8.09l-8.09-8.09l8.09-8.09L72.03,82.32z M52.99,79.47l-8.09-8.09
		l8.09-8.09l8.09,8.09L52.99,79.47z M50.13,82.32l-8.09,8.09l-8.09-8.09l8.09-8.09L50.13,82.32z M31.1,79.47l-3.72-3.72l-1.33-7.4
		l5.05-5.05l8.09,8.09L31.1,79.47z M31.1,85.18l8.09,8.09l-7.35,7.35L29.38,86.9L31.1,85.18z M102.85,63.65l-3.22-3.22l4.67-4.67
		L102.85,63.65z M96.78,41.4l8.09,8.09l-8.09,8.09l-8.09-8.09L96.78,41.4z M85.83,52.34l8.09,8.09l-8.09,8.09l-8.09-8.09
		L85.83,52.34z M74.88,41.4l8.09,8.09l-8.09,8.09l-8.09-8.09L74.88,41.4z M72.03,60.43l-8.09,8.09l-8.09-8.09l8.09-8.09L72.03,60.43
		z M52.99,41.4l8.09,8.09l-8.09,8.09l-8.09-8.09L52.99,41.4z M50.13,60.43l-8.09,8.09l-8.09-8.09l8.09-8.09L50.13,60.43z M31.1,41.4
		l8.09,8.09l-8.09,8.09l-8.09-8.09L31.1,41.4z M28.24,60.43l-3.06,3.06l-1.34-7.47L28.24,60.43z"/>
	
		<radialGradient id="SVGID_2_" cx="65.5303" cy="12.9983" r="52.279" gradientTransform="matrix(1 0 0 0.4505 0 7.1421)" gradientUnits="userSpaceOnUse">
		<stop  offset="0.7216" style="stop-color:#94D1E0"/>
		<stop  offset="1" style="stop-color:#94D1E0;stop-opacity:0"/>
	</radialGradient>
	<path style="fill:url(#SVGID_2_);" d="M107.47,24.48l-8.06-8.06l2.29-2.29c-1.08-0.97-3.87-1.84-3.87-1.84l-1.27,1.27l-2.07-2.07
		c-4.25-1.51-7.07-1.35-7.07-1.35l6.28,6.28l-8.09,8.09l-8.09-8.09l6.66-6.66c-2.61-0.8-5.06-0.66-5.06-0.66l-4.46,4.46L69.5,8.41
		l-5.57,0.15l7.86,7.86l-8.09,8.09l-8.09-8.09l7.88-7.88l-5.94,0.22l-4.8,4.8l-4.72-4.72L43,9.51l6.91,6.91l-8.09,8.09l-8.09-8.09
		l6.31-6.31c0,0-5.64,0.76-7.28,1.56l-1.89,1.89l-1.18-1.18c0,0-2.25,0.34-4.09,1.63l2.41,2.41l-7.24,7.24c0,0,0.42,1.65,2.81,2.9
		l7.29-7.29l8.09,8.09l-4.22,4.22c0,0,2.74,1.55,4.75,0.97l2.33-2.33l5.87,5.87l9.87,0.29l6.15-6.15l5.98,5.98l10.29-0.36l5.62-5.62
		l2.5,2.5c2.67,0.26,4.81-0.9,4.81-0.9l-4.45-4.45l8.09-8.09l8.09,8.09C104.64,27.37,107.12,25.86,107.47,24.48z M52.77,35.46
		l-8.09-8.09l8.09-8.09l8.09,8.09L52.77,35.46z M74.66,35.46l-8.09-8.09l8.09-8.09l8.09,8.09L74.66,35.46z"/>
	<path style="fill:#84B0C1;" d="M64,4C34.17,4,9.99,9.9,9.99,22.74c0,10.24,24.18,18.74,54.01,18.74c29.83,0,54.01-8.5,54.01-18.74
		C118.01,11.29,93.83,4,64,4z M64,34.36c-24.01,0-43.47-5.98-43.47-13.35c0-7.37,19.46-11.69,43.47-11.69
		c24.01,0,43.47,4.32,43.47,11.69C107.47,28.38,88.01,34.36,64,34.36z"/>
	<path style="fill:#A8E3F0;" d="M107.47,15.75c2.07,1.65,3.91,4.42,1.7,6.98c-1.95,2.26-1.41,2.81-0.24,2.51
		c2.2-0.56,5.84-3.03,4.61-7.19c-1.25-4.2-8.44-7-13.26-7.99c-1.31-0.27-3.5-0.56-3.89,0C96.01,10.63,102.77,12,107.47,15.75z"/>
	<g>
		<path style="fill:#A8E3F0;" d="M37.24,35.27c-4.64-0.47-16.02-1.62-22.14-9.69c-2.24-2.96-2.06-7.28,0.44-9.75
			c4.34-4.27,10.01-4.41,8.72-3.62c-3.45,2.11-10.3,5.44-4.58,12.31c5.85,7.03,20.26,8.86,22.61,9.22S44.76,36.02,37.24,35.27z"/>
	</g>
</g>
</svg>
'@
    rename = @'
<svg xmlns="http://www.w3.org/2000/svg" width="280" height="220" viewBox="0 0 280 220">
  <!-- Oberes Quadrat (grau, geschlossen) -->
  <path d="M 40 120 L 40 40 L 160 40 L 160 90 L 130 120 Z" fill="none" stroke="#4a7ebb" stroke-width="6"/>
  <text x="65" y="105" font-family="Arial, sans-serif" font-size="70" font-weight="bold" fill="#666666">ab</text>
  
  <!-- Untere Input-Box (breiter) -->
  <rect x="60" y="90" width="190" height="90" fill="white" stroke="#999999" stroke-width="4"/>
  
  <!-- Text in der Input-Box: abc -->
  <text x="72" y="160" font-family="Arial, sans-serif" font-size="80" font-weight="bold" fill="#4a7ebb">abc</text>
  
  <!-- Cursor als drei separate Textelemente -->
 <g fill="#FF0000">  
  <!-- Pipe (senkrechter Strich U+007C) -->
  <text x="213.5" y="160" font-family="Arial, sans-serif" lengthAdjust="spacingAndGlyphs" textLength="40" font-size="100" font-weight="bold"  text-anchor="middle">|</text>
  
  <!-- Oberer Arrowhead (U+2304, normal) -->
  <text x="213.5" y="95" font-family="Arial, sans-serif"  lengthAdjust="spacingAndGlyphs" textLength="60" font-size="40" font-weight="bold" text-anchor="middle">V</text>

  <!-- Unterer Arrowhead (U+2304, gedreht um 180 Grad) -->
  <text x="186" y="70" font-family="Arial, sans-serif" lengthAdjust="spacingAndGlyphs" textLength="60" font-size="40" font-weight="bold" transform="rotate(180, 215, 125)">V</text>
  </g>
</svg>
'@
    play = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Generator: Adobe Illustrator 25.2.3, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
<svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
	 viewBox="0 0 128 128" style="enable-background:new 0 0 128 128;" xml:space="preserve">
<g>
	<path style="fill:#F77E00;" d="M116.46,3.96h-104c-4.42,0-8,3.58-8,8v104c0,4.42,3.58,8,8,8h104c4.42,0,8-3.58,8-8v-104
		C124.46,7.54,120.88,3.96,116.46,3.96z"/>
	<path style="fill:#FF9800;" d="M110.16,3.96h-98.2c-4.13,0.03-7.47,3.37-7.5,7.5v97.9c-0.01,4.14,3.34,7.49,7.48,7.5
		c0.01,0,0.01,0,0.02,0h98.1c4.14,0.01,7.49-3.34,7.5-7.48c0-0.01,0-0.01,0-0.02v-97.9c0.09-4.05-3.13-7.41-7.18-7.5
		C110.31,3.96,110.23,3.96,110.16,3.96z"/>
	<path style="opacity:0.75;fill:#FFBD52;enable-background:new    ;" d="M40.16,12.86c0-2.3-1.6-3-10.8-2.7
		c-7.7,0.3-11.5,1.2-13.8,4s-2.9,8.5-3,15.3c0,4.8,0,9.3,2.5,9.3c3.4,0,3.4-7.9,6.2-12.3C26.66,17.76,40.16,15.86,40.16,12.86z"/>
</g>
<g>
	<path style="fill:#FAFAFA;" d="M43.7,62.21v-25.7c-0.03-1.25,0.96-2.28,2.21-2.31c0.42-0.01,0.83,0.1,1.19,0.31l43.5,25.7
		c1.13,0.72,1.47,2.22,0.75,3.35c-0.19,0.3-0.45,0.55-0.75,0.75l-43.5,25.6c-1.08,0.63-2.46,0.27-3.09-0.81
		c-0.21-0.36-0.32-0.77-0.31-1.19V62.21z"/>
</g>
</svg>
'@
    folder = @'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <g transform="translate(1.4065934065934016 1.4065934065934016) scale(2.81 2.81)">
    <!-- Ordner-Hintergrund (gelb) -->
    <path d="M 73.538 35.162 l -52.548 1.952 c -1.739 0 -2.753 0.651 -3.232 2.323 L 6.85 76.754 c -0.451 1.586 -2.613 2.328 -4.117 2.328 h 0 C 1.23 79.082 0 77.852 0 76.349 l 0 -10.458 V 23.046 v -2.047 v -6.273 c 0 -2.103 1.705 -3.808 3.808 -3.808 h 27.056 c 1.01 0 1.978 0.401 2.692 1.115 l 7.85 7.85 c 0.714 0.714 1.683 1.115 2.692 1.115 H 69.73 c 2.103 0 3.808 1.705 3.808 3.808 v 1.301 L 73.538 35.162 z" fill="rgb(224,173,49)" stroke="none"/>
    
    <!-- Weisses Blatt im Ordner -->
    <path d="M 63.726 14.605 v 54.54 c 0 1.386 -1.124 2.51 -2.51 2.51 H 13.02 c -1.386 0 -2.51 -1.124 -2.51 -2.51 V 2.51 c 0 -1.386 1.124 -2.51 2.51 -2.51 H 49.12 C 51.554 6.059 56.533 10.874 63.726 14.605 z" fill="rgb(233,233,224)" stroke="none"/>
    <path d="M 63.726 14.605 H 51.407 c -1.263 0 -2.287 -1.024 -2.287 -2.287 V 0 L 63.726 14.605 z" fill="rgb(217,215,202)" stroke="none"/>
    
    <!-- Linien auf dem Blatt -->
    <path d="M 52.978 23.363 H 20.139 c -0.829 0 -1.5 -0.671 -1.5 -1.5 s 0.671 -1.5 1.5 -1.5 h 32.839 c 0.828 0 1.5 0.671 1.5 1.5 S 53.806 23.363 52.978 23.363 z" fill="rgb(217,215,202)" stroke="none"/>
    <path d="M 52.978 30.363 H 20.139 c -0.829 0 -1.5 -0.671 -1.5 -1.5 s 0.671 -1.5 1.5 -1.5 h 32.839 c 0.828 0 1.5 0.671 1.5 1.5 S 53.806 30.363 52.978 30.363 z" fill="rgb(217,215,202)" stroke="none"/>
    
    <!-- Unterer gelber Bereich (der Tab) -->
    <path d="M 2.733 79.082 L 2.733 79.082 c 1.503 0 2.282 -1.147 2.733 -2.733 l 10.996 -38.362 c 0.479 -1.672 2.008 -2.824 3.748 -2.824 h 67.379 c 1.609 0 2.765 1.546 2.311 3.09 L 79.004 75.279 c -0.492 1.751 -1.571 3.818 -3.803 3.803 H 2.733 z" fill="rgb(255,200,67)" stroke="none"/>
    
    <!-- Noten (aus zweitem Icon, unten im gelben Bereich) -->
    <g transform="translate(40, 38) scale(1.85)" fill="#000000">
      <path d="M10.653,8.76l8.145-1.321v11.043c0,0.914-0.681,1.644-1.744,1.913c-1.168,0.289-2.294-0.2-2.519-1.095c-0.224-0.897,0.541-1.858,1.708-2.15c0.527-0.13,1.047-0.103,1.481,0.05v-6.654l-5.969,1.092l-0.028,8.276c-0.005,0.783-0.713,1.554-1.729,1.805c-1.153,0.289-2.363-0.26-2.492-1.081c-0.221-0.886,0.534-1.837,1.691-2.127c0.52-0.13,1.029-0.104,1.456,0.046V8.76z" fill="#328c98"/>
      <path d="M7.591,12.81L7.62,2.581c0,0,2.228-0.119,4.407,3.298c0,0,0.006-1.764-1.669-3.055C7.087,0.54,7.096,0,7.096,0C6.472,0.073,6.408,0.547,6.408,0.547v10.771c-0.468-0.164-1.028-0.193-1.602-0.05c-1.27,0.314-2.1,1.363-1.857,2.338c0.143,0.901,1.471,1.506,2.74,1.187c1.115-0.278,1.894-1.12,1.9-1.983H7.591z" fill="coral"/>
      <path d="M13.515,6.2c0.388-0.097,0.659-0.39,0.661-0.69h0.001l0.01-3.559c0,0,0.775-0.041,1.533,1.148c0,0,0.001-0.614-0.582-1.062C14,1.242,14.004,1.054,14.004,1.054c-0.217,0.025-0.24,0.19-0.24,0.19v3.748c-0.162-0.058-0.356-0.068-0.556-0.019c-0.443,0.109-0.73,0.475-0.646,0.814C12.612,6.101,13.074,6.311,13.515,6.2z" fill="red"/>
      <path d="M17.355,6.209c0.27-0.067,0.458-0.272,0.46-0.481l0.007-2.479c0,0,0.54-0.029,1.068,0.799c0,0,0.001-0.428-0.404-0.74c-0.793-0.554-0.791-0.685-0.791-0.685c-0.151,0.018-0.167,0.133-0.167,0.133v2.611c-0.113-0.04-0.249-0.047-0.388-0.012c-0.308,0.076-0.509,0.33-0.45,0.566C16.724,6.14,17.046,6.287,17.355,6.209z" fill="blue"/>
    </g>
  </g>
</svg>
'@
    web = @'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <circle cx="64" cy="64" r="50" fill="#eaf7ff" stroke="#1f5fa8" stroke-width="8"/>
  <ellipse cx="64" cy="64" rx="22" ry="50" fill="none" stroke="#1f5fa8" stroke-width="6"/>
  <path d="M16 64h96M27 38h74M27 90h74" fill="none" stroke="#1f5fa8" stroke-width="6" stroke-linecap="round"/>
  <path d="M64 14v100" fill="none" stroke="#1f5fa8" stroke-width="6" stroke-linecap="round"/>
</svg>
'@
}

$script:Recordings = New-Object System.Collections.ArrayList
$script:GridSortColumn = 'Erstellt'
$script:GridSortDescending = $true
$script:IsSyncingRecordingsFromFolder = $false
$script:FfmpegProcess = $null
$script:CurrentOutputFile = $null
$script:CurrentRecordNumber = 0
$script:IsRecording = $false
$script:IsPaused = $false
$script:Stopwatch = New-Object System.Diagnostics.Stopwatch
$script:Random = New-Object Random
$script:CurrentBytes = 0L
$script:CurrentView = 'Standard'
$script:SyncingSettings = $false
$script:Recorder = $null
$script:NativeLogPath = Join-Path $script:BaseDir 'recorder-native-csharp.log'
$script:NativeLevel = 0.0
$script:RestoreTopMostOnReturn = $false
$script:Player = $null
$script:IsPlaying = $false
$script:CurrentPlaybackFile = ''
$script:LauncherKind = if ([string]::IsNullOrWhiteSpace($LauncherKind)) { 'BAT' } else { [string]$LauncherKind }
$script:LauncherLogPath = [string]$LauncherLogPath
$script:SpeedCommanderVersion = [string]$SpeedCommanderVersion
$script:InactivePath = [string]$InactivePath
$script:InactiveSelection = [string]$InactiveSelection
$script:InactiveFocused = [string]$InactiveFocused
$script:LastReturnSyncUtc = [datetime]::MinValue
$script:PlaybackAlias = 'SystemtonRecorderPlayback'

function Write-Log {
    param([string]$Text)
    try {
        $line = ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Text)
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
        try { Add-Content -LiteralPath $script:NativeLogPath -Value $line -Encoding UTF8 } catch {}
    } catch {}
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}


function Get-WavDurationFromFile {
    param([string]$Path)
    try {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $br = New-Object System.IO.BinaryReader($fs)
            $riff = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($riff -ne 'RIFF') { return '' }
            [void]$br.ReadUInt32()
            $wave = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($wave -ne 'WAVE') { return '' }
            $byteRate = 0
            $dataSize = 0
            while ($fs.Position -lt ($fs.Length - 8)) {
                $chunkId = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
                $chunkSize = [int64]$br.ReadUInt32()
                $chunkStart = $fs.Position
                if ($chunkId -eq 'fmt ') {
                    [void]$br.ReadUInt16()
                    [void]$br.ReadUInt16()
                    [void]$br.ReadUInt32()
                    $byteRate = [int64]$br.ReadUInt32()
                } elseif ($chunkId -eq 'data') {
                    $dataSize = $chunkSize
                }
                $next = $chunkStart + $chunkSize
                if (($chunkSize % 2) -eq 1) { $next++ }
                if ($next -le $fs.Length) { $fs.Position = $next } else { break }
                if ($byteRate -gt 0 -and $dataSize -gt 0) { break }
            }
            if ($byteRate -gt 0 -and $dataSize -gt 0) {
                return (Format-Duration ([TimeSpan]::FromSeconds([double]$dataSize / [double]$byteRate)))
            }
        } finally {
            try { $fs.Close() } catch {}
        }
    } catch {
        Write-Log "Dauerberechnung WAV fehlgeschlagen: $($_.Exception.Message)"
    }
    return ''
}

function Get-AudioDurationFromFile {
    param([string]$Path)
    try {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
        $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        if ($ext -eq '.wav') { return Get-WavDurationFromFile $Path }
        # Für MP3/M4A versucht Windows Shell die Länge aus den Dateieigenschaften zu lesen.
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace((Split-Path -Parent $Path))
            if ($folder) {
                $item = $folder.ParseName((Split-Path -Leaf $Path))
                if ($item) {
                    for ($i = 0; $i -lt 320; $i++) {
                        $name = $folder.GetDetailsOf($null, $i)
                        if ($name -match 'Länge|Length|Dauer|Duration') {
                            $val = $folder.GetDetailsOf($item, $i)
                            if (-not [string]::IsNullOrWhiteSpace($val)) { return [string]$val }
                        }
                    }
                }
            }
        } catch {}
    } catch {
        Write-Log "Dauerberechnung fehlgeschlagen: $($_.Exception.Message)"
    }
    return ''
}

function Load-Config {
    try {
        if (Test-Path -LiteralPath $script:ConfigPath) {
            $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $json = $raw | ConvertFrom-Json
                foreach ($p in $json.PSObject.Properties) {
                    if ($script:Config.Contains($p.Name)) { $script:Config[$p.Name] = $p.Value }
                }
            }
        }
    } catch { Write-Log "Konfiguration konnte nicht geladen werden: $($_.Exception.Message)" }
    Ensure-Directory $script:Config.outputDir
}

function Save-Config {
    try { $script:Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8 }
    catch { Write-Log "Konfiguration konnte nicht gespeichert werden: $($_.Exception.Message)" }
}

function Get-ObjValue {
    param(
        [object]$Obj,
        [string]$Name,
        [object]$Default = ''
    )

    if ($null -eq $Obj) { return $Default }

    try {
        $prop = $Obj.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $Default }
        if ($null -eq $prop.Value) { return $Default }
        return $prop.Value
    } catch {
        return $Default
    }
}

function Normalize-RecordingItem {
    param([object]$Item)

    $pfad = [string](Get-ObjValue $Item 'Pfad' '')
    $dateiname = [string](Get-ObjValue $Item 'Dateiname' '')
    if ([string]::IsNullOrWhiteSpace($dateiname) -and -not [string]::IsNullOrWhiteSpace($pfad)) {
        $dateiname = [IO.Path]::GetFileName($pfad)
    }

    $nummer = Get-ObjValue $Item 'Nummer' 0
    try { $nummer = [int]$nummer } catch { $nummer = 0 }

    $status = [string](Get-ObjValue $Item 'Status' 'OK')
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'OK' }

    $dauer = [string](Get-ObjValue $Item 'Dauer' '')
    if ([string]::IsNullOrWhiteSpace($dauer) -or $dauer -eq '00:00:00') {
        $dauerCalc = Get-AudioDurationFromFile $pfad
        if (-not [string]::IsNullOrWhiteSpace($dauerCalc)) { $dauer = $dauerCalc }
    }
    if ([string]::IsNullOrWhiteSpace($dauer)) { $dauer = '00:00:00' }

    return [pscustomobject]@{
        Nummer   = $nummer
        Status   = $status
        Dateiname = $dateiname
        Dauer    = $dauer
        Groesse  = [string](Get-ObjValue $Item 'Groesse' '')
        Kuenstler = [string](Get-ObjValue $Item 'Kuenstler' '')
        Album    = [string](Get-ObjValue $Item 'Album' '')
        Jahr     = [string](Get-ObjValue $Item 'Jahr' '')
        Pfad     = $pfad
        Erstellt  = [string](Get-ObjValue $Item 'Erstellt' '')
    }
}

function Load-Recordings {
    $script:Recordings.Clear() | Out-Null
    try {
        if (Test-Path -LiteralPath $script:IndexPath) {
            $raw = Get-Content -LiteralPath $script:IndexPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                foreach ($item in @($raw | ConvertFrom-Json)) {
                    [void]$script:Recordings.Add((Normalize-RecordingItem $item))
                }
            }
        }
    } catch { Write-Log "Aufnahmeindex konnte nicht geladen werden: $($_.Exception.Message)" }
}

function Save-Recordings {
    try { @($script:Recordings) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:IndexPath -Encoding UTF8 }
    catch { Write-Log "Aufnahmeindex konnte nicht gespeichert werden: $($_.Exception.Message)" }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1048576) { return ('{0:N1} KB' -f ($Bytes / 1024)) }
    if ($Bytes -lt 1073741824) { return ('{0:N2} MB' -f ($Bytes / 1048576)) }
    return ('{0:N2} GB' -f ($Bytes / 1073741824))
}

function Format-Duration {
    param([TimeSpan]$Duration)
    return ('{0:00}:{1:00}:{2:00}' -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
}

function Quote-Arg {
    param([string]$s)
    if ($null -eq $s) { return '""' }
    return '"' + ($s -replace '"','\"') + '"'
}

function Asset-Path {
    param([string]$Name)
    return (Join-Path $script:AssetsDir $Name)
}

function Get-ConfigChildValue {
    param(
        [object]$Obj,
        [string]$Name,
        [object]$Default = $null
    )
    try {
        if ($null -eq $Obj) { return $Default }
        if ($Obj -is [hashtable] -or $Obj -is [System.Collections.IDictionary]) {
            if ($Obj.Contains($Name)) { return $Obj[$Name] }
            return $Default
        }
        $prop = $Obj.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $Default }
        if ($null -eq $prop.Value) { return $Default }
        return $prop.Value
    } catch { return $Default }
}

function Resolve-ConfigIconPath {
    param([string]$IconName)

    if ([string]::IsNullOrWhiteSpace($IconName)) { return '' }
    try {
        if ([System.IO.Path]::IsPathRooted($IconName)) { return $IconName }
    } catch {}

    $iconDir = [string](Get-ConfigChildValue $script:Config 'iconDir' 'assets')
    if ([string]::IsNullOrWhiteSpace($iconDir)) { $iconDir = 'assets' }

    $base = $iconDir
    try {
        if (-not [System.IO.Path]::IsPathRooted($base)) {
            $base = Join-Path $script:BaseDir $base
        }
    } catch {
        $base = $script:AssetsDir
    }

    return (Join-Path $base $IconName)
}

function Get-IconSetting {
    param(
        [string]$Key,
        [string]$Field,
        [string]$Default = ''
    )

    try {
        $all = Get-ConfigChildValue $script:Config 'icons' $null
        $one = Get-ConfigChildValue $all $Key $null
        $val = Get-ConfigChildValue $one $Field $Default
        if ([string]::IsNullOrWhiteSpace([string]$val)) { return $Default }
        return [string]$val
    } catch { return $Default }
}

function Get-IconFile {
    param([string]$Key, [string]$Default = '')
    return (Get-IconSetting $Key 'file' $Default)
}

function Get-IconNameText {
    param([string]$Key, [string]$Default = '')
    return (Get-IconSetting $Key 'name' $Default)
}

function Get-IconShortcutText {
    param([string]$Key, [string]$Default = '')
    return (Get-IconSetting $Key 'shortcut' $Default)
}

function Get-ActionIconSetting {
    param(
        [string]$Key,
        [string]$Field,
        [string]$Default = ''
    )

    try {
        # Neue zentrale Icon-Konfiguration zuerst nutzen.
        $fromIcons = Get-IconSetting $Key $Field ''
        if (-not [string]::IsNullOrWhiteSpace([string]$fromIcons)) { return [string]$fromIcons }

        # Alte actionIcons-Konfiguration bleibt als Rueckwaertskompatibilitaet erhalten.
        $all = Get-ConfigChildValue $script:Config 'actionIcons' $null
        $one = Get-ConfigChildValue $all $Key $null
        $val = Get-ConfigChildValue $one $Field $Default
        if ([string]::IsNullOrWhiteSpace([string]$val)) { return $Default }
        return [string]$val
    } catch { return $Default }
}


function Ensure-EmbeddedIconAsset {
    param(
        [string]$Key,
        [string]$DefaultFile,
        [int]$Size = 64
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Key)) { return }
        $file = Get-IconFile $Key $DefaultFile
        if ([string]::IsNullOrWhiteSpace($file)) { return }

        $ext = ''
        try { $ext = [IO.Path]::GetExtension($file).ToLowerInvariant() } catch {}
        if ($ext -eq '.ico') { return }

        $targetPng = Resolve-ConfigIconPath $file
        if (Test-Path -LiteralPath $targetPng) { return }

        $svg = $null
        try { $svg = $script:EmbeddedSvgIcons[$Key] } catch {}
        if ([string]::IsNullOrWhiteSpace([string]$svg)) { return }

        $targetDir = Split-Path -Parent $targetPng
        if (-not [string]::IsNullOrWhiteSpace($targetDir)) { Ensure-Directory $targetDir }

        # SVG-Quelle neben der PNG-Datei wiederherstellen.
        try {
            $svgPath = [IO.Path]::ChangeExtension($targetPng, '.svg')
            if (-not (Test-Path -LiteralPath $svgPath)) {
                Set-Content -LiteralPath $svgPath -Value $svg -Encoding UTF8
                Write-Log "Icon-SVG wiederhergestellt: $svgPath"
            }
        } catch {
            Write-Log "Icon-SVG konnte nicht geschrieben werden: $Key -> $($_.Exception.Message)"
        }

        # Optional rendern, wenn Svg.dll vorhanden ist.
        $svgDllCandidates = @(
            (Join-Path $script:BaseDir 'lib\Svg.dll'),
            (Join-Path $script:BaseDir 'Svg.dll')
        )

        $svgDll = $null
        foreach ($c in $svgDllCandidates) {
            if (Test-Path -LiteralPath $c) { $svgDll = $c; break }
        }

        if (-not $svgDll) {
            Write-Log "Icon-PNG fehlt, SVG-Quelle ist vorhanden, aber lib\\Svg.dll fehlt: $Key / $file"
            return
        }

        try {
            Add-Type -Path $svgDll -ErrorAction SilentlyContinue
        } catch {
            Write-Log "Svg.dll konnte nicht geladen werden: $($_.Exception.Message)"
            return
        }

        try {
            $svgDoc = [Svg.SvgDocument]::FromXml([string]$svg)
            $svgDoc.Width = $Size
            $svgDoc.Height = $Size
            $bitmap = $svgDoc.Draw()
            $bitmap.Save($targetPng, [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
            Write-Log "Icon-PNG aus eingebettetem SVG erzeugt: $targetPng"
        } catch {
            Write-Log "Icon-PNG konnte nicht aus SVG erzeugt werden: $Key -> $($_.Exception.Message)"
        }
    } catch {
        Write-Log "Ensure-EmbeddedIconAsset Fehler: $Key -> $($_.Exception.Message)"
    }
}

function Load-ConfiguredIconImage {
    param(
        [string]$Key,
        [string]$DefaultFile,
        [int]$Size = 24
    )
    Ensure-EmbeddedIconAsset $Key $DefaultFile ([Math]::Max($Size, 64))
    $file = Get-IconFile $Key $DefaultFile
    $p = Resolve-ConfigIconPath $file
    try {
        if (Test-Path -LiteralPath $p) {
            if ([IO.Path]::GetExtension($p).ToLowerInvariant() -eq '.ico') {
                $ico = New-Object System.Drawing.Icon($p)
                $src = $ico.ToBitmap()
                $ico.Dispose()
            } else {
                $src = [System.Drawing.Image]::FromFile($p)
            }
            if ($Size -le 0) { return $src }
            $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($src, 0, 0, $Size, $Size)
            $g.Dispose()
            try { $src.Dispose() } catch {}
            return $bmp
        }
    } catch { Write-Log "Icon konnte nicht geladen werden: $Key / $file -> $($_.Exception.Message)" }
    return $null
}

function Get-ActionButtonTipText {
    param(
        [string]$Key,
        [string]$DefaultName,
        [string]$DefaultShortcut,
        [string]$Suffix = ''
    )
    $name = Get-ActionIconSetting $Key 'name' $DefaultName
    $shortcut = Get-ActionIconSetting $Key 'shortcut' $DefaultShortcut
    if (-not [string]::IsNullOrWhiteSpace($Suffix)) { $name = "$name $Suffix" }
    if ([string]::IsNullOrWhiteSpace($shortcut)) { return $name }
    return ("{0}: {1}" -f $name, $shortcut)
}

function Load-ImageSafe {
    param([string]$Name)
    $p = Resolve-ConfigIconPath $Name
    try { if (Test-Path -LiteralPath $p) { return [System.Drawing.Image]::FromFile($p) } } catch {}
    try {
        $p2 = Asset-Path $Name
        if (Test-Path -LiteralPath $p2) { return [System.Drawing.Image]::FromFile($p2) }
    } catch {}
    return $null
}


function Load-EmbeddedPng {
    param([string]$Base64Text)
    try {
        $bytes = [Convert]::FromBase64String($Base64Text)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $bmp = New-Object System.Drawing.Bitmap($img)
        $img.Dispose()
        $ms.Dispose()
        return $bmp
    } catch { return $null }
}

function Load-MicrophoneImage {
    # Zuerst externe Datei erlauben, damit du das Symbol später einfach austauschen kannst.
    foreach ($name in @('icon-microphone.png','mikrofon.png')) {
        $img = Load-ImageSafe $name
        if ($img) { return $img }
    }

    # Fallback: das von dir gelieferte Mikrofon-Symbol ist direkt eingebettet.
    return Load-EmbeddedPng @'
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
'@
}


function Add-NativeWasapiType {
$code = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace Systemton {
    public class NativeWasapiLoopbackRecorder : IDisposable {
        private Thread thread;
        private volatile bool stopRequested;
        private volatile bool paused;
        private ManualResetEventSlim started = new ManualResetEventSlim(false);
        private string startError;
        private string outputPath;
        private bool captureEndpoint;
        private double level;
        private long bytesWritten;
        private FileStream stream;
        private byte[] fmtBytes;
        private ushort channels;
        private uint sampleRate;
        private ushort bitsPerSample;
        private ushort blockAlign;
        private bool isFloat;

        public double Level { get { return level; } }
        public long BytesWritten { get { return bytesWritten; } }
        public bool IsRunning { get { return thread != null && thread.IsAlive; } }
        public bool IsPaused { get { return paused; } set { paused = value; } }

        public void Start(string wavPath) { Start(wavPath, false); }

        public void Start(string wavPath, bool useMicrophoneEndpoint) {
            if (IsRunning) throw new InvalidOperationException("Recorder läuft bereits.");
            outputPath = wavPath;
            captureEndpoint = useMicrophoneEndpoint;
            stopRequested = false;
            paused = false;
            startError = null;
            bytesWritten = 0;
            level = 0;
            started.Reset();
            thread = new Thread(CaptureThread);
            thread.IsBackground = true;
            thread.Name = "NativeWasapiLoopbackRecorder";
            thread.SetApartmentState(ApartmentState.MTA);
            thread.Start();
            if (!started.Wait(5000)) throw new Exception("WASAPI-Start dauerte länger als 5 Sekunden.");
            if (!String.IsNullOrEmpty(startError)) throw new Exception(startError);
        }

        public void Stop() {
            stopRequested = true;
            if (thread != null && thread.IsAlive) thread.Join(5000);
        }

        public void Dispose() { try { Stop(); } catch {} }

        private void CaptureThread() {
            IAudioClient audioClient = null;
            IAudioCaptureClient captureClient = null;
            try {
                Guid iidAudioClient = typeof(IAudioClient).GUID;
                Guid iidCaptureClient = typeof(IAudioCaptureClient).GUID;
                Guid session = Guid.Empty;

                var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
                IMMDevice device;
                EDataFlow flow = captureEndpoint ? EDataFlow.eCapture : EDataFlow.eRender;
                int hr = enumerator.GetDefaultAudioEndpoint(flow, ERole.eConsole, out device);
                Check(hr, captureEndpoint ? "GetDefaultAudioEndpoint(CAPTURE)" : "GetDefaultAudioEndpoint(LOOPBACK)");

                object obj;
                hr = device.Activate(ref iidAudioClient, CLSCTX.CLSCTX_ALL, IntPtr.Zero, out obj);
                Check(hr, "IMMDevice.Activate(IAudioClient)");
                audioClient = (IAudioClient)obj;

                IntPtr fmtPtr;
                hr = audioClient.GetMixFormat(out fmtPtr);
                Check(hr, "IAudioClient.GetMixFormat");

                WAVEFORMATEX wf = (WAVEFORMATEX)Marshal.PtrToStructure(fmtPtr, typeof(WAVEFORMATEX));
                int fmtSize = 18 + wf.cbSize;
                fmtBytes = new byte[fmtSize];
                Marshal.Copy(fmtPtr, fmtBytes, 0, fmtSize);

                channels = wf.nChannels;
                sampleRate = wf.nSamplesPerSec;
                bitsPerSample = wf.wBitsPerSample;
                blockAlign = wf.nBlockAlign;
                isFloat = IsFloatFormat(wf, fmtBytes);

                const int AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000;
                int streamFlags = captureEndpoint ? 0 : AUDCLNT_STREAMFLAGS_LOOPBACK;
                hr = audioClient.Initialize(AUDCLNT_SHAREMODE.AUDCLNT_SHAREMODE_SHARED, streamFlags, 10000000, 0, fmtPtr, ref session);
                Marshal.FreeCoTaskMem(fmtPtr);
                Check(hr, captureEndpoint ? "IAudioClient.Initialize(CAPTURE)" : "IAudioClient.Initialize(LOOPBACK)");

                object capObj;
                hr = audioClient.GetService(ref iidCaptureClient, out capObj);
                Check(hr, "IAudioClient.GetService(IAudioCaptureClient)");
                captureClient = (IAudioCaptureClient)capObj;

                stream = new FileStream(outputPath, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
                WriteWaveHeader(stream, fmtBytes, 0);

                hr = audioClient.Start();
                Check(hr, "IAudioClient.Start");
                started.Set();

                while (!stopRequested) {
                    uint packetFrames;
                    hr = captureClient.GetNextPacketSize(out packetFrames);
                    if (hr < 0) break;
                    if (packetFrames == 0) { Thread.Sleep(10); continue; }

                    while (packetFrames > 0) {
                        IntPtr data;
                        uint frames;
                        int flags;
                        long devPos, qpcPos;
                        hr = captureClient.GetBuffer(out data, out frames, out flags, out devPos, out qpcPos);
                        if (hr < 0) { stopRequested = true; break; }
                        int byteCount = checked((int)(frames * blockAlign));
                        byte[] buffer = new byte[byteCount];
                        if ((flags & 0x2) == 0 && data != IntPtr.Zero) Marshal.Copy(data, buffer, 0, byteCount);
                        level = CalculatePeak(buffer);
                        if (!paused) {
                            stream.Write(buffer, 0, buffer.Length);
                            bytesWritten += buffer.Length;
                        }
                        captureClient.ReleaseBuffer(frames);
                        hr = captureClient.GetNextPacketSize(out packetFrames);
                        if (hr < 0) { packetFrames = 0; stopRequested = true; }
                    }
                }

                try { audioClient.Stop(); } catch {}
                FinalizeWaveHeader();
            } catch (Exception ex) {
                startError = ex.Message;
                started.Set();
                try { FinalizeWaveHeader(); } catch {}
            } finally {
                try { if (stream != null) stream.Dispose(); } catch {}
                try { if (captureClient != null) Marshal.ReleaseComObject(captureClient); } catch {}
                try { if (audioClient != null) Marshal.ReleaseComObject(audioClient); } catch {}
            }
        }

        private double CalculatePeak(byte[] buffer) {
            if (buffer == null || buffer.Length == 0) return 0;
            double max = 0;
            if (isFloat && bitsPerSample == 32) {
                for (int i = 0; i + 3 < buffer.Length; i += 4) {
                    float v = BitConverter.ToSingle(buffer, i);
                    double a = Math.Abs(v);
                    if (a > max) max = a;
                }
            } else if (bitsPerSample == 16) {
                for (int i = 0; i + 1 < buffer.Length; i += 2) {
                    short v = BitConverter.ToInt16(buffer, i);
                    double a = Math.Abs(v / 32768.0);
                    if (a > max) max = a;
                }
            } else if (bitsPerSample == 24) {
                for (int i = 0; i + 2 < buffer.Length; i += 3) {
                    int v = buffer[i] | (buffer[i+1] << 8) | (buffer[i+2] << 16);
                    if ((v & 0x800000) != 0) v |= unchecked((int)0xff000000);
                    double a = Math.Abs(v / 8388608.0);
                    if (a > max) max = a;
                }
            }
            if (max > 1) max = 1;
            return max;
        }

        private bool IsFloatFormat(WAVEFORMATEX wf, byte[] bytes) {
            if (wf.wFormatTag == 3) return true;
            if (wf.wFormatTag == 0xFFFE && bytes.Length >= 40) {
                int data1 = BitConverter.ToInt32(bytes, 24);
                return data1 == 3;
            }
            return false;
        }

        private void WriteWaveHeader(Stream s, byte[] fmt, long dataSize) {
            BinaryWriter bw = new BinaryWriter(s);
            bw.Write(new char[] { 'R','I','F','F' });
            bw.Write((uint)(4 + 8 + fmt.Length + 8 + dataSize));
            bw.Write(new char[] { 'W','A','V','E' });
            bw.Write(new char[] { 'f','m','t',' ' });
            bw.Write((uint)fmt.Length);
            bw.Write(fmt);
            bw.Write(new char[] { 'd','a','t','a' });
            bw.Write((uint)dataSize);
        }

        private void FinalizeWaveHeader() {
            if (stream == null || fmtBytes == null) return;
            long pos = stream.Position;
            stream.Seek(0, SeekOrigin.Begin);
            WriteWaveHeader(stream, fmtBytes, bytesWritten);
            stream.Seek(pos, SeekOrigin.Begin);
            stream.Flush();
        }

        private void Check(int hr, string where) {
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        }
    }

    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }
    public enum AUDCLNT_SHAREMODE { AUDCLNT_SHAREMODE_SHARED = 0, AUDCLNT_SHAREMODE_EXCLUSIVE = 1 }

    [Flags]
    public enum CLSCTX : uint {
        CLSCTX_INPROC_SERVER = 0x1,
        CLSCTX_INPROC_HANDLER = 0x2,
        CLSCTX_LOCAL_SERVER = 0x4,
        CLSCTX_REMOTE_SERVER = 0x10,
        CLSCTX_ALL = CLSCTX_INPROC_SERVER | CLSCTX_INPROC_HANDLER | CLSCTX_LOCAL_SERVER | CLSCTX_REMOTE_SERVER
    }

    [StructLayout(LayoutKind.Sequential, Pack=2)]
    public struct WAVEFORMATEX {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, uint dwStateMask, out object ppDevices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        int GetDevice(string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate(ref Guid iid, CLSCTX dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(uint stgmAccess, out object ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out uint pdwState);
    }

    [ComImport]
    [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioClient {
        int Initialize(AUDCLNT_SHAREMODE ShareMode, int StreamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, ref Guid AudioSessionGuid);
        int GetBufferSize(out uint pNumBufferFrames);
        int GetStreamLatency(out long phnsLatency);
        int GetCurrentPadding(out uint pNumPaddingFrames);
        int IsFormatSupported(AUDCLNT_SHAREMODE ShareMode, IntPtr pFormat, out IntPtr ppClosestMatch);
        int GetMixFormat(out IntPtr ppDeviceFormat);
        int GetDevicePeriod(out long phnsDefaultDevicePeriod, out long phnsMinimumDevicePeriod);
        int Start();
        int Stop();
        int Reset();
        int SetEventHandle(IntPtr eventHandle);
        int GetService(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
    }

    [ComImport]
    [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioCaptureClient {
        int GetBuffer(out IntPtr ppData, out uint pNumFramesToRead, out int pdwFlags, out long pu64DevicePosition, out long pu64QPCPosition);
        int ReleaseBuffer(uint NumFramesRead);
        int GetNextPacketSize(out uint pNumFramesInNextPacket);
    }
}
'@
    try {
        if (-not ('Systemton.NativeWasapiLoopbackRecorder' -as [type])) {
            Add-Type -TypeDefinition $code -Language CSharp -ReferencedAssemblies @('System.dll') -ErrorAction Stop
            Write-Log 'C# WASAPI-Komponente erfolgreich kompiliert.'
        }
    } catch {
        Write-Log "C# WASAPI-Komponente konnte nicht kompiliert werden: $($_.Exception.Message)" 'ERROR'
        throw
    }
}


function Find-FFmpeg {
    $candidates = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($script:Config.ffmpegPath)) { [void]$candidates.Add($script:Config.ffmpegPath) }
    [void]$candidates.Add((Join-Path $script:BaseDir 'ffmpeg.exe'))
    [void]$candidates.Add((Join-Path $script:BaseDir 'bin\ffmpeg.exe'))
    [void]$candidates.Add((Join-Path $script:BaseDir 'ffmpeg\bin\ffmpeg.exe'))
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    try {
        $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
    } catch {}
    return $null
}

function Get-Extension {
    switch ($script:Config.format) {
        'WAV' { return '.wav' }
        'M4A' { return '.m4a' }
        default { return '.mp3' }
    }
}

function Get-CodecArgs {
    switch ($script:Config.format) {
        'WAV' { return '-c:a pcm_s16le' }
        'M4A' {
            switch ($script:Config.quality) {
                'Niedrig' { return '-c:a aac -b:a 96k' }
                'Hoch'    { return '-c:a aac -b:a 256k' }
                default   { return '-c:a aac -b:a 160k' }
            }
        }
        default {
            switch ($script:Config.quality) {
                'Niedrig' { return '-c:a libmp3lame -b:a 96k' }
                'Hoch'    { return '-c:a libmp3lame -b:a 256k' }
                default   { return '-c:a libmp3lame -b:a 160k' }
            }
        }
    }
}

function Build-FFmpegArguments {
    param([string]$OutputFile)
    $codec = Get-CodecArgs
    $out = Quote-Arg $OutputFile
    switch ($script:Config.source) {
        'Mikrofon' { return "-y -hide_banner -f wasapi -i default $codec $out" }
        'System-Sound + Mikrofon' { return "-y -hide_banner -f wasapi -i loopback_system=true -f wasapi -i default -filter_complex amix=inputs=2:duration=longest -ac 2 $codec $out" }
        default { return "-y -hide_banner -f wasapi -i loopback_system=true $codec $out" }
    }
}

function Get-NextNumber {
    $max = 0
    foreach ($r in @($script:Recordings)) { try { $n = [int](Get-ObjValue $r 'Nummer' 0); if ($n -gt $max) { $max = $n } } catch {} }
    try {
        if (Test-Path -LiteralPath $script:Config.outputDir) {
            Get-ChildItem -LiteralPath $script:Config.outputDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.BaseName -match '_(\d+)$') { $n = [int]$matches[1]; if ($n -gt $max) { $max = $n } }
            }
        }
    } catch {}
    return ($max + 1)
}


function Sync-RecordingsFromFolder {
    if ($script:IsSyncingRecordingsFromFolder) { return }
    $script:IsSyncingRecordingsFromFolder = $true
    try {
        if (-not $script:Config -or [string]::IsNullOrWhiteSpace([string]$script:Config.outputDir)) { return }
        if (-not (Test-Path -LiteralPath $script:Config.outputDir)) { return }

        $known = @{}
        foreach ($r in @($script:Recordings)) {
            $p = [string](Get-ObjValue $r 'Pfad' '')
            if (-not [string]::IsNullOrWhiteSpace($p)) { $known[$p.ToLowerInvariant()] = $true }
        }

        $changed = $false
        $files = Get-ChildItem -LiteralPath $script:Config.outputDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -match '^(?i)\.(wav|mp3|m4a)$'
        } | Sort-Object LastWriteTime

        foreach ($f in @($files)) {
            $key = $f.FullName.ToLowerInvariant()
            if ($known.ContainsKey($key)) { continue }
            $num = 0
            if ($f.BaseName -match '_(\d+)$') { try { $num = [int]$matches[1] } catch { $num = 0 } }
            if ($num -le 0) { $num = Get-NextNumber }
            $obj = [pscustomobject]@{
                Nummer = $num
                Status = if ($f.Length -lt 1024) { 'Warnung' } else { 'Fertig' }
                Dateiname = $f.Name
                Dauer = (Get-AudioDurationFromFile $f.FullName)
                Groesse = (Format-Bytes $f.Length)
                Kuenstler = ''
                Album = ''
                Jahr = $f.LastWriteTime.Year
                Pfad = $f.FullName
                Erstellt = $f.CreationTime.ToString('s')
            }
            [void]$script:Recordings.Add($obj)
            $known[$key] = $true
            $changed = $true
            Write-Log "Dateiliste: vorhandene Aufnahme aus Ordner ergänzt: $($f.FullName)"
        }
        if ($changed) { Save-Recordings }
    } catch {
        Write-Log "Dateiliste: Ordnerabgleich fehlgeschlagen: $($_.Exception.Message)"
    } finally {
        $script:IsSyncingRecordingsFromFolder = $false
    }
}

function Convert-DurationToSeconds {
    param([string]$Text)
    try {
        if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
        $parts = ([string]$Text).Trim() -split ':'
        if ($parts.Count -eq 3) {
            return (([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2])
        }
        if ($parts.Count -eq 2) { return (([int]$parts[0] * 60) + [int]$parts[1]) }
    } catch {}
    return 0
}

function Convert-SizeToBytes {
    param([string]$Text)
    try {
        if ([string]::IsNullOrWhiteSpace($Text)) { return 0L }
        $t = ([string]$Text).Trim().Replace(',', '.')
        if ($t -match '^([0-9.]+)\s*(B|KB|MB|GB)$') {
            $v = [double]$matches[1]
            switch ($matches[2]) {
                'GB' { return [int64]($v * 1073741824) }
                'MB' { return [int64]($v * 1048576) }
                'KB' { return [int64]($v * 1024) }
                default { return [int64]$v }
            }
        }
    } catch {}
    return 0L
}

function Get-RecordingSortValue {
    param([object]$Item, [string]$ColumnName)
    $r = Normalize-RecordingItem $Item
    switch ($ColumnName) {
        'StatusIcon' { return [string](Get-ObjValue $r 'Status' '') }
        'Dateiname'  { return ([string](Get-ObjValue $r 'Dateiname' '')).ToLowerInvariant() }
        'Dauer'      { return (Convert-DurationToSeconds ([string](Get-ObjValue $r 'Dauer' ''))) }
        'Groesse'    { return (Convert-SizeToBytes ([string](Get-ObjValue $r 'Groesse' ''))) }
        'Format'     {
            $pfad = [string](Get-ObjValue $r 'Pfad' '')
            if (-not [string]::IsNullOrWhiteSpace($pfad)) { return ([IO.Path]::GetExtension($pfad)).TrimStart('.').ToUpperInvariant() }
            return ([IO.Path]::GetExtension([string](Get-ObjValue $r 'Dateiname' ''))).TrimStart('.').ToUpperInvariant()
        }
        'Erstellt'   {
            $e = [string](Get-ObjValue $r 'Erstellt' '')
            try { if (-not [string]::IsNullOrWhiteSpace($e)) { return [datetime]$e } } catch {}
            $pfad = [string](Get-ObjValue $r 'Pfad' '')
            try { if (Test-Path -LiteralPath $pfad) { return (Get-Item -LiteralPath $pfad).CreationTime } } catch {}
            return [datetime]::MinValue
        }
        'Nummer'     { try { return [int](Get-ObjValue $r 'Nummer' 0) } catch { return 0 } }
        'Pfad'       { return ([string](Get-ObjValue $r 'Pfad' '')).ToLowerInvariant() }
        default      { return ([string](Get-ObjValue $r 'Dateiname' '')).ToLowerInvariant() }
    }
}

function Apply-RecordingSort {
    param([switch]$Save)
    try {
        if (-not $script:Recordings) { return }
        $col = if ([string]::IsNullOrWhiteSpace([string]$script:GridSortColumn)) { 'Erstellt' } else { [string]$script:GridSortColumn }
        if ($script:GridSortDescending) {
            $sorted = @($script:Recordings) | Sort-Object -Descending -Property @{ Expression = { Get-RecordingSortValue $_ $col } }, @{ Expression = { ([string](Get-ObjValue $_ 'Dateiname' '')).ToLowerInvariant() } }
        } else {
            $sorted = @($script:Recordings) | Sort-Object -Property @{ Expression = { Get-RecordingSortValue $_ $col } }, @{ Expression = { ([string](Get-ObjValue $_ 'Dateiname' '')).ToLowerInvariant() } }
        }
        $script:Recordings.Clear() | Out-Null
        foreach ($item in @($sorted)) { [void]$script:Recordings.Add($item) }
        if ($Save) { Save-Recordings }
    } catch {
        Write-Log "Sortierung fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Update-GridSortGlyphs {
    try {
        if (-not $grid) { return }
        foreach ($c in $grid.Columns) { $c.HeaderCell.SortGlyphDirection = [System.Windows.Forms.SortOrder]::None }
        if ($grid.Columns.Contains($script:GridSortColumn)) {
            $grid.Columns[$script:GridSortColumn].HeaderCell.SortGlyphDirection = if ($script:GridSortDescending) { [System.Windows.Forms.SortOrder]::Descending } else { [System.Windows.Forms.SortOrder]::Ascending }
        }
    } catch {}
}

function Sort-GridByColumn {
    param([int]$ColumnIndex)
    try {
        if (-not $grid -or $ColumnIndex -lt 0 -or $ColumnIndex -ge $grid.Columns.Count) { return }
        $colName = [string]$grid.Columns[$ColumnIndex].Name
        if ([string]::IsNullOrWhiteSpace($colName)) { return }
        if ($script:GridSortColumn -eq $colName) {
            $script:GridSortDescending = -not [bool]$script:GridSortDescending
        } else {
            $script:GridSortColumn = $colName
            # Bei Datum und Nummer ist absteigend meistens hilfreicher: neueste/höchste zuerst.
            $script:GridSortDescending = ($colName -eq 'Erstellt' -or $colName -eq 'Nummer')
        }
        Apply-RecordingSort -Save
        Refresh-Grid
        Write-Log "Dateiliste sortiert: Spalte=$script:GridSortColumn Richtung=$(if ($script:GridSortDescending) { 'absteigend' } else { 'aufsteigend' })."
    } catch {
        Write-Log "Sortierklick fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Refresh-Grid {
    if (-not $grid) { return }
    Sync-RecordingsFromFolder
    Apply-RecordingSort
    $grid.Rows.Clear()
    try { $grid.ColumnHeadersVisible = $true; $grid.Visible = $true; $grid.BringToFront(); $filesPanel.BringToFront() } catch {}
    foreach ($rawItem in @($script:Recordings)) {
        $r = Normalize-RecordingItem $rawItem
        try {
            if (([string](Get-ObjValue $rawItem 'Dauer' '')).Trim() -eq '' -and -not [string]::IsNullOrWhiteSpace([string](Get-ObjValue $r 'Dauer' ''))) {
                $rawItem.Dauer = [string](Get-ObjValue $r 'Dauer' '')
            }
        } catch {}
        $status = [string](Get-ObjValue $r 'Status' 'OK')
        $icon = if ($status -eq 'Warnung') { '⚠' } else { '✓' }
        $pfad = [string](Get-ObjValue $r 'Pfad' '')
        $formatAnzeige = ''
        try {
            if (-not [string]::IsNullOrWhiteSpace($pfad)) { $formatAnzeige = ([IO.Path]::GetExtension($pfad)).TrimStart('.').ToUpperInvariant() }
            if ([string]::IsNullOrWhiteSpace($formatAnzeige)) { $formatAnzeige = ([IO.Path]::GetExtension([string](Get-ObjValue $r 'Dateiname' ''))).TrimStart('.').ToUpperInvariant() }
        } catch { $formatAnzeige = '' }
        $erstelltAnzeige = [string](Get-ObjValue $r 'Erstellt' '')
        if ([string]::IsNullOrWhiteSpace($erstelltAnzeige)) { $erstelltAnzeige = [string](Get-ObjValue $r 'Jahr' '') }
        $idx = $grid.Rows.Add(
            $icon,
            (Get-ObjValue $r 'Dateiname' ''),
            (Get-ObjValue $r 'Dauer' '00:00:00'),
            (Get-ObjValue $r 'Groesse' ''),
            $formatAnzeige,
            $erstelltAnzeige,
            (Get-ObjValue $r 'Nummer' ''),
            $pfad
        )
        if ($status -eq 'Warnung') { $grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::DarkGoldenrod }
    }
    Update-GridSortGlyphs
    Write-Log "Dateiliste aktualisiert: $($grid.Rows.Count) Eintrag/Einträge. Sortierung=$script:GridSortColumn/$script:GridSortDescending."
}

function Select-RecordingInGrid {
    param([string]$FilePath)
    if (-not $grid -or -not $FilePath) { return }
    try {
        $grid.ClearSelection()
        for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
            $rowPath = [string]$grid.Rows[$i].Cells['Pfad'].Value
            if ($rowPath -eq $FilePath) {
                $grid.Rows[$i].Selected = $true
                $grid.CurrentCell = $grid.Rows[$i].Cells['Dateiname']
                try { $grid.FirstDisplayedScrollingRowIndex = $i } catch {}
                return
            }
        }
    } catch {
        Write-Log "Dateiliste markieren fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Sync-AfterExternalReturn {
    param([string]$Reason = 'Aktivierung')

    try {
        # Nicht während einer Aufnahme in die Liste greifen.
        if ($script:IsRecording) { return }

        # Mehrfaches Activated-Flackern vermeiden.
        $now = [datetime]::UtcNow
        try {
            if ((New-TimeSpan -Start $script:LastReturnSyncUtc -End $now).TotalMilliseconds -lt 900) { return }
        } catch {}
        $script:LastReturnSyncUtc = $now

        $selectedPath = ''
        try { $selectedPath = Get-SelectedRecordingPath } catch {}

        Write-Log "Rückkehr erkannt: $Reason. Aufnahmeordner wird abgeglichen."
        Refresh-Grid

        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            Select-RecordingInGrid -FilePath $selectedPath
        }

        if ($lblStatus) { $lblStatus.Text = 'Ordner abgeglichen.' }
    } catch {
        Write-Log "Abgleich nach Rückkehr fehlgeschlagen: $($_.Exception.Message)"
    }
}


function Add-RecordingToIndex {
    param([string]$FilePath, [int]$Number, [TimeSpan]$Duration, [string]$Status)
    foreach ($existing in @($script:Recordings)) {
        if ([string](Get-ObjValue $existing 'Pfad' '') -eq $FilePath) {
            try { $existing.Status = $Status; $existing.Dauer = (Format-Duration $Duration) } catch {}
            Save-Recordings
            Refresh-Grid
            return
        }
    }
    $size = 0L
    try { if (Test-Path -LiteralPath $FilePath) { $size = (Get-Item -LiteralPath $FilePath).Length } } catch {}
    $obj = [pscustomobject]@{
        Nummer = $Number
        Status = $Status
        Dateiname = [IO.Path]::GetFileName($FilePath)
        Dauer = (Format-Duration $Duration)
        Groesse = (Format-Bytes $size)
        Kuenstler = ''
        Album = ''
        Jahr = (Get-Date).Year
        Pfad = $FilePath
        Erstellt = (Get-Date).ToString('s')
    }
    [void]$script:Recordings.Add($obj)
    Save-Recordings
    Refresh-Grid
}

function Update-StatusLine {
    $elapsed = Format-Duration $script:Stopwatch.Elapsed
    if ($script:IsRecording) {
        $lblStatus.Text = if ($script:IsPaused) { "Pause … $elapsed" } else { "Aufzeichnung … $elapsed" }
    } else { $lblStatus.Text = 'Bereit.' }
    $lblTime.Text = $elapsed
    if ($script:IsRecording -and $script:Recorder) {
        try { $script:CurrentBytes = [long]$script:Recorder.BytesWritten } catch { $script:CurrentBytes = 0 }
        $lblSize.Text = Format-Bytes $script:CurrentBytes
    } elseif ($script:CurrentOutputFile -and (Test-Path -LiteralPath $script:CurrentOutputFile)) {
        try { $script:CurrentBytes = (Get-Item -LiteralPath $script:CurrentOutputFile).Length } catch { $script:CurrentBytes = 0 }
        $lblSize.Text = Format-Bytes $script:CurrentBytes
    } else { $lblSize.Text = '' }
}

function Set-RecordingUiState {
    if ($script:IsRecording) {
        if ($script:IsPaused) {
            $btnStartPause.Text = 'Weiter'
            Set-ToolbarButtonIcon $btnStartPause 'resume' 'icon_resume.png'
        } else {
            $btnStartPause.Text = 'Pause'
            Set-ToolbarButtonIcon $btnStartPause 'pause' 'icon_pause.png'
        }
        $btnStop.Enabled = $true
    } else {
        $btnStartPause.Text = 'Start'
        Set-ToolbarButtonIcon $btnStartPause 'start' 'icon_start.png'
        # Der Stopp-Button ist auch während interner Wiedergabe aktiv.
        $btnStop.Enabled = [bool]$script:IsPlaying
    }
    Update-ToolbarStates
}

function Start-Recording {
    try {
        Write-Log 'Start-Recording: native C# WASAPI-Loopback.'
        Ensure-Directory $script:Config.outputDir
        $num = Get-NextNumber
        $script:CurrentRecordNumber = $num
        $file = Join-Path $script:Config.outputDir ('Aufnahme_{0:000}.wav' -f $num)
        $script:CurrentOutputFile = $file

        if (-not ('Systemton.NativeWasapiLoopbackRecorder' -as [type])) {
            throw 'Native C# WASAPI-Komponente ist nicht geladen.'
        }

        $script:Recorder = New-Object Systemton.NativeWasapiLoopbackRecorder
        $useMicEndpoint = ($script:Config.source -eq 'Mikrofon')
        if ($script:Config.source -eq 'System-Sound + Mikrofon') {
            Write-Log 'Hinweis: Mischaufnahme System-Sound + Mikrofon ist in dieser nativen Teststufe noch nicht gemischt; aufgenommen wird System-Sound.'
        }
        Write-Log "Native Aufnahme startet: $file Quelle=$($script:Config.source) Mikrofon=$($script:Config.microphoneDevice)"
        $script:Recorder.Start($file, [bool]$useMicEndpoint)

        $script:IsRecording = $true
        $script:IsPaused = $false
        $script:NativeLevel = 0.0
        $script:Stopwatch.Reset()
        $script:Stopwatch.Start()
        Set-RecordingUiState
        $lblStatus.Text = 'Aufzeichnung gestartet.'
        Write-Log 'Native Aufnahme läuft.'
    } catch {
        Write-Log "Startfehler native Aufnahme: $($_.Exception.Message)"
        try { if ($script:Recorder) { $script:Recorder.Dispose() } } catch {}
        $script:Recorder = $null
        [System.Windows.Forms.MessageBox]::Show("Die Aufnahme konnte nicht gestartet werden.`r`n`r`n$($_.Exception.Message)`r`n`r`nLog:`r`n$script:LogPath", 'Fehler', 'OK', 'Error') | Out-Null
        $script:IsRecording = $false
        $script:IsPaused = $false
        Set-RecordingUiState
    }
}

function Toggle-StartPause {
    if (-not $script:IsRecording) { Start-Recording; return }
    if (-not $script:Recorder) { return }
    try {
        if ($script:IsPaused) {
            $script:Recorder.IsPaused = $false
            $script:IsPaused = $false
            $script:Stopwatch.Start()
            Write-Log 'Aufnahme fortgesetzt.'
        } else {
            $script:Recorder.IsPaused = $true
            $script:IsPaused = $true
            $script:Stopwatch.Stop()
            Write-Log 'Aufnahme pausiert.'
        }
        Set-RecordingUiState
    } catch {
        Write-Log "Pause/Fortsetzen fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Pause/Fortsetzen ist fehlgeschlagen.`r`n`r`n$($_.Exception.Message)", 'Fehler', 'OK', 'Warning') | Out-Null
    }
}

function Stop-Recording {
    if (-not $script:IsRecording) { return }
    $duration = $script:Stopwatch.Elapsed
    try {
        Write-Log 'Stop-Recording: native Aufnahme wird beendet.'
        $script:Stopwatch.Stop()
        if ($script:Recorder) {
            try { $script:Recorder.Stop() } catch { Write-Log "Native Stop-Warnung: $($_.Exception.Message)" }
            try { $script:Recorder.Dispose() } catch {}
        }

        $status = 'Fertig'
        if (-not (Test-Path -LiteralPath $script:CurrentOutputFile)) { $status = 'Warnung' }
        else { try { if ((Get-Item -LiteralPath $script:CurrentOutputFile).Length -lt 1024) { $status = 'Warnung' } } catch { $status = 'Warnung' } }

        Add-RecordingToIndex -FilePath $script:CurrentOutputFile -Number $script:CurrentRecordNumber -Duration $duration -Status $status
        $lblStatus.Text = if ($status -eq 'Fertig') { 'Aufnahme gespeichert.' } else { 'Aufnahme beendet, aber Datei prüfen.' }
        Write-Log "Native Aufnahme beendet. Status=$status Datei=$script:CurrentOutputFile"
        # Nicht mehr in den Explorer springen: die Aufnahme gehoert direkt in die interne Dateiliste.
        # Nach dem Speichern wird die Tabelle zuverlässig geöffnet und die neue Aufnahme markiert.
        Refresh-Grid
        Show-View 'Files'
        Select-RecordingInGrid -FilePath $script:CurrentOutputFile
        Write-Log "Dateiliste nach Aufnahme geöffnet: Rows=$($grid.Rows.Count), Datei=$script:CurrentOutputFile"
    } catch {
        Write-Log "Stoppfehler native Aufnahme: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Die Aufnahme konnte nicht sauber beendet werden.`r`n`r`n$($_.Exception.Message)", 'Fehler', 'OK', 'Error') | Out-Null
    } finally {
        $script:IsRecording = $false
        $script:IsPaused = $false
        $script:Recorder = $null
        $script:NativeLevel = 0.0
        # Nach Stopp soll die große Zeitanzeige wieder bereit/neutral sein.
        try { $script:Stopwatch.Reset() } catch {}
        Set-RecordingUiState
        Update-StatusLine
    }
}

function Delete-SelectedRecording {
    if ($grid.SelectedRows.Count -lt 1) { return }
    $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
    $name = [string]$grid.SelectedRows[0].Cells['Dateiname'].Value
    if ([System.Windows.Forms.MessageBox]::Show("Soll diese Aufnahme wirklich gelöscht werden?`r`n`r`n$name", 'Aufnahme löschen', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
        for ($i = $script:Recordings.Count - 1; $i -ge 0; $i--) { if ([string](Get-ObjValue $script:Recordings[$i] 'Pfad' '') -eq $path) { $script:Recordings.RemoveAt($i) } }
        Save-Recordings; Refresh-Grid; $lblStatus.Text = 'Aufnahme gelöscht.'
    } catch { [System.Windows.Forms.MessageBox]::Show("Die Aufnahme konnte nicht gelöscht werden.`r`n`r`n$($_.Exception.Message)", 'Fehler', 'OK', 'Error') | Out-Null }
}

function Remove-SelectedFromList {
    if ($grid.SelectedRows.Count -lt 1) { return }
    $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
    for ($i = $script:Recordings.Count - 1; $i -ge 0; $i--) { if ([string](Get-ObjValue $script:Recordings[$i] 'Pfad' '') -eq $path) { $script:Recordings.RemoveAt($i) } }
    Save-Recordings; Refresh-Grid; $lblStatus.Text = 'Eintrag entfernt. Datei bleibt erhalten.'
}

function Rename-SelectedRecording {
    if ($grid.SelectedRows.Count -lt 1) { return }
    $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
    if (-not (Test-Path -LiteralPath $path)) { return }

    $oldName = [IO.Path]::GetFileNameWithoutExtension($path)
    $ext = [IO.Path]::GetExtension($path)

    # Wenn "Recorder im Vordergrund halten" aktiv ist, darf der Eingabedialog nicht
    # hinter die GUI gedrückt werden. Darum TopMost für die Dauer des Dialogs deaktivieren.
    $wasTopMost = $false
    try {
        $wasTopMost = [bool]$form.TopMost
        if ($wasTopMost) {
            $form.TopMost = $false
            Write-Log 'Vordergrundmodus für Umbenennen-Dialog deaktiviert.'
        }
    } catch {}

    $newName = ''
    try {
        $newName = [Microsoft.VisualBasic.Interaction]::InputBox('Neuer Dateiname ohne Endung:', 'Aufnahme umbenennen', $oldName)
    } finally {
        try {
            if ($wasTopMost -and [bool]$script:Config.alwaysOnTop) {
                $form.TopMost = $true
                Write-Log 'Vordergrundmodus nach Umbenennen-Dialog wieder aktiviert.'
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($newName)) { return }
    $newName = ($newName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($newName)) { return }

    $newPath = Join-Path ([IO.Path]::GetDirectoryName($path)) ($newName + $ext)
    try {
        Rename-Item -LiteralPath $path -NewName ($newName + $ext) -Force
        foreach ($r in @($script:Recordings)) {
            if ([string](Get-ObjValue $r 'Pfad' '') -eq $path) {
                $r.Pfad = $newPath
                $r.Dateiname = [IO.Path]::GetFileName($newPath)
            }
        }
        Save-Recordings
        Refresh-Grid
        Select-RecordingInGrid -FilePath $newPath
        $lblStatus.Text = 'Aufnahme umbenannt.'
        Write-Log "Aufnahme umbenannt: $path -> $newPath"
    } catch {
        Write-Log "Umbenennen fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Umbenennen fehlgeschlagen.`r`n`r`n$($_.Exception.Message)", 'Fehler', 'OK', 'Error') | Out-Null
    }
}

function Ensure-MciPlayerType {
    try {
        if ('RecorderMciPlayer' -as [type]) { return $true }

        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class RecorderMciPlayer {
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    private static extern int mciSendString(string command, StringBuilder returnValue, int returnLength, IntPtr winHandle);

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    private static extern bool mciGetErrorString(int errorCode, StringBuilder errorText, int errorTextSize);

    public static string ErrorText(int code) {
        if (code == 0) return "";
        StringBuilder sb = new StringBuilder(512);
        if (mciGetErrorString(code, sb, sb.Capacity)) return sb.ToString();
        return "MCI Fehlercode " + code.ToString();
    }

    public static void Send(string command) {
        int rc = mciSendString(command, null, 0, IntPtr.Zero);
        if (rc != 0) throw new Exception(ErrorText(rc) + " | Befehl: " + command);
    }

    public static void CloseSilently(string aliasName) {
        int rc = mciSendString("close " + aliasName, null, 0, IntPtr.Zero);
    }

    public static void Open(string filePath, string aliasName) {
        CloseSilently(aliasName);
        string escaped = filePath.Replace("\"", "");
        Send("open \"" + escaped + "\" type mpegvideo alias " + aliasName);
    }

    public static void Play(string aliasName) {
        Send("play " + aliasName);
    }

    public static void Stop(string aliasName) {
        try { Send("stop " + aliasName); } catch {}
        CloseSilently(aliasName);
    }
}
"@ -ErrorAction Stop
        Write-Log 'MCI-Audioplayer bereit.'
        return $true
    } catch {
        Write-Log "MCI-Audioplayer konnte nicht geladen werden: $($_.Exception.Message)"
        return $false
    }
}

function Stop-Playback {
    try {
        if ($script:IsPlaying -or -not [string]::IsNullOrWhiteSpace($script:CurrentPlaybackFile)) {
            if (Ensure-MciPlayerType) {
                try { [RecorderMciPlayer]::Stop($script:PlaybackAlias) } catch {}
            }
            Write-Log "Wiedergabe gestoppt: $script:CurrentPlaybackFile"
        }
    } catch {
        Write-Log "Wiedergabe konnte nicht sauber gestoppt werden: $($_.Exception.Message)"
    } finally {
        $script:Player = $null
        $script:IsPlaying = $false
        $script:CurrentPlaybackFile = ''
        # Wiedergabe-Stopp ebenfalls neutralisieren, damit die Uhr nicht auf dem alten Stand bleibt.
        try { $script:Stopwatch.Reset() } catch {}
        if ($lblStatus) { $lblStatus.Text = 'Wiedergabe gestoppt.' }
        Set-RecordingUiState
        Update-StatusLine
    }
}

function Play-SelectedRecording {
    if ($grid.SelectedRows.Count -lt 1) { return }
    $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return }

    try {
        # Wenn bereits etwas läuft, zuerst sauber stoppen.
        if ($script:IsPlaying) { Stop-Playback }

        if (-not (Ensure-MciPlayerType)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Der interne MCI-Player konnte nicht geladen werden.`r`n`r`nDie Datei wird nicht extern geöffnet.",
                'Abspielen',
                'OK',
                'Error'
            ) | Out-Null
            return
        }

        # WinMM/MCI spielt intern ohne externes Programmfenster und ohne WPF-Initialisierung.
        # Dadurch darf die WinForms-GUI beim Abspielen nicht mehr springen oder kleiner skalieren.
        [RecorderMciPlayer]::Open($path, $script:PlaybackAlias)
        [RecorderMciPlayer]::Play($script:PlaybackAlias)

        $script:Player = $script:PlaybackAlias
        $script:IsPlaying = $true
        $script:CurrentPlaybackFile = $path
        if ($lblStatus) { $lblStatus.Text = 'Wiedergabe läuft. Stopp beendet das Abspielen.' }
        Write-Log "Interne Wiedergabe über MCI gestartet: $path"
        Set-RecordingUiState
    } catch {
        try { if (Ensure-MciPlayerType) { [RecorderMciPlayer]::Stop($script:PlaybackAlias) } } catch {}
        $script:IsPlaying = $false
        $script:Player = $null
        $script:CurrentPlaybackFile = ''
        Set-RecordingUiState
        Write-Log "Wiedergabe fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Die Datei konnte nicht direkt abgespielt werden.`r`n`r`n$($_.Exception.Message)", 'Abspielen', 'OK', 'Error') | Out-Null
    }
}

function Stop-RecordingOrPlayback {
    if ($script:IsPlaying) {
        Stop-Playback
        return
    }
    Stop-Recording
}


function Get-SelectedRecordingPath {
    try {
        if ($grid -and $grid.SelectedRows.Count -ge 1) {
            $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
            if (-not [string]::IsNullOrWhiteSpace($path)) { return $path }
        }
    } catch {}
    return ''
}

function Is-SpeedCommanderLaunch {
    try {
        if ([string]::IsNullOrWhiteSpace($script:LauncherKind)) { return $false }
        return ([string]$script:LauncherKind).ToLowerInvariant() -in @('speedcommander','sc','scmac')
    } catch { return $false }
}

function Find-SpeedCommanderExe {
    try {
        if ($script:Config.speedCommanderExe -and (Test-Path -LiteralPath $script:Config.speedCommanderExe)) { return [string]$script:Config.speedCommanderExe }
    } catch {}
    try {
        $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'SpeedCommander|SpeedCmd' } | Select-Object -First 1
        if ($p) {
            try { if ($p.MainModule.FileName -and (Test-Path -LiteralPath $p.MainModule.FileName)) { return $p.MainModule.FileName } } catch {}
        }
    } catch {}
    $candidates = @(
        "$env:ProgramFiles\SpeedProject\SpeedCommander\SpeedCommander.exe",
        "$env:ProgramFiles\SpeedCommander\SpeedCommander.exe",
        "${env:ProgramFiles(x86)}\SpeedProject\SpeedCommander\SpeedCommander.exe",
        "${env:ProgramFiles(x86)}\SpeedCommander\SpeedCommander.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return ''
}

function Jump-ToSelectedRecording {
    $path = Get-SelectedRecordingPath
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        [System.Windows.Forms.MessageBox]::Show('Bitte zuerst eine vorhandene Aufnahme in der Tabelle markieren.', 'Zu Datei springen', 'OK', 'Information') | Out-Null
        return
    }
    $folder = Split-Path -Parent $path
    Write-Log "Zu Datei springen: $path"
    try { [System.Windows.Forms.Clipboard]::SetText($path) } catch {}

    $wasTopMost = $false
    try { $wasTopMost = [bool]$form.TopMost; $form.TopMost = $false } catch {}

    try {
        if (Is-SpeedCommanderLaunch) {
            $sc = Find-SpeedCommanderExe
            if (-not [string]::IsNullOrWhiteSpace($sc)) {
                # SpeedCommander direkt mit der Datei aufrufen:
                # <Pfad>\SpeedCommander.exe <Pfad der zu selektierenden Datei>
                Start-Process -FilePath $sc -ArgumentList ('"{0}"' -f $path) | Out-Null
                $lblStatus.Text = 'Datei in SpeedCommander geöffnet/markiert. Dateipfad ist in der Zwischenablage.'
                Write-Log "SpeedCommander gestartet: $sc Datei=$path"
            } else {
                Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $path) | Out-Null
                $lblStatus.Text = 'Datei im Explorer markiert. SpeedCommander-Pfad fehlt.'
                Write-Log 'SpeedCommander-Start erkannt, aber SpeedCommander.exe nicht gefunden; Explorer-Fallback verwendet.'
            }
        } else {
            # BAT/normaler Start: bewusst Explorer verwenden, auch wenn SpeedCommander installiert ist.
            Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $path) | Out-Null
            $lblStatus.Text = 'Datei im Explorer markiert.'
            Write-Log 'Zu Datei: BAT/normaler Start erkannt; Explorer verwendet.'
        }
    } catch {
        Write-Log "Zu Datei springen fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Die Datei konnte nicht geöffnet werden.`r`n`r`n$($_.Exception.Message)", 'Fehler', 'OK', 'Error') | Out-Null
    } finally {
        # Nicht sofort wieder TopMost aktivieren, sonst springt der Recorder direkt vor SpeedCommander.
        # Beim Zurückklicken auf den Recorder wird der Vordergrundmodus wiederhergestellt.
        $script:RestoreTopMostOnReturn = ($wasTopMost -and [bool]$script:Config.alwaysOnTop)
    }
}

function Save-OutputFolderFromTextBox {
    try {
        if (-not $txtOutput) { return }
        $p = [string]$txtOutput.Text
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        $p = $p.Trim()
        Ensure-Directory $p
        $script:Config.outputDir = $p
        Save-Config
        Sync-RecordingsFromFolder
        Write-Log "Speicherordner per Eingabefeld gesetzt: $p"
        if ($lblStatus) { $lblStatus.Text = 'Speicherordner gespeichert.' }
    } catch {
        Write-Log "Speicherordner konnte nicht gesetzt werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(('Der Speicherordner konnte nicht gesetzt werden:`r`n`r`n' + $_.Exception.Message), 'Speicherordner', 'OK', 'Warning') | Out-Null
        Sync-SettingsToControls
    }
}

function Open-SelectedFolder {
    if ($grid.SelectedRows.Count -ge 1) {
        $path = [string]$grid.SelectedRows[0].Cells['Pfad'].Value
        if ($path -and (Test-Path -LiteralPath $path)) { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $path); return }
    }
    if (Test-Path -LiteralPath $script:Config.outputDir) { Start-Process explorer.exe -ArgumentList (Quote-Arg $script:Config.outputDir) }
}

function Choose-OutputFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Speicherordner für Aufnahmen wählen'
    $dlg.SelectedPath = $script:Config.outputDir
    if ($dlg.ShowDialog() -eq 'OK') { $script:Config.outputDir = $dlg.SelectedPath; Save-Config; Sync-SettingsToControls }
}

function Normalize-WebUrl {
    param([string]$Url)
    $u = ([string]$Url).Trim()
    if ([string]::IsNullOrWhiteSpace($u)) { return '' }
    if ($u -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $u = 'https://' + $u }
    return $u
}

function Save-WebUrlFromTextBox {
    try {
        if (-not $txtWebUrl) { return }
        $u = Normalize-WebUrl ([string]$txtWebUrl.Text)
        if ([string]::IsNullOrWhiteSpace($u)) { return }
        $script:Config.webUrl = $u
        $txtWebUrl.Text = $u
        Save-Config
        Write-Log "Webseite gespeichert: $u"
        if ($lblStatus) { $lblStatus.Text = 'Webseite gespeichert.' }
    } catch {
        Write-Log "Webseite konnte nicht gespeichert werden: $($_.Exception.Message)"
    }
}

function Open-ConfiguredWebsite {
    try {
        if ($txtWebUrl) { Save-WebUrlFromTextBox }
        $u = Normalize-WebUrl ([string]$script:Config.webUrl)
        if ([string]::IsNullOrWhiteSpace($u)) {
            [System.Windows.Forms.MessageBox]::Show('Bitte zuerst eine Webseite eintragen.', 'Webseite öffnen', 'OK', 'Information') | Out-Null
            return
        }

        $wasTopMost = $false
        try {
            $wasTopMost = [bool]$form.TopMost
            if ($wasTopMost) {
                $form.TopMost = $false
                Write-Log 'Vordergrundmodus für Webseite kurz deaktiviert.'
            }
        } catch {}

        Write-Log "Webseite-Aufruf gestartet: $u"
        Start-Process -FilePath 'explorer.exe' -ArgumentList $u | Out-Null
        $script:RestoreTopMostOnReturn = ($wasTopMost -and [bool]$script:Config.alwaysOnTop)
        if ($lblStatus) { $lblStatus.Text = 'Webseite geöffnet.' }
        Write-Log "Webseite geöffnet: $u"
    } catch {
        Write-Log "Webseite konnte nicht geöffnet werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(('Die Webseite konnte nicht geöffnet werden:`r`n`r`n' + $_.Exception.Message), 'Webseite öffnen', 'OK', 'Warning') | Out-Null
    }
}

function Choose-FFmpeg {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'ffmpeg.exe|ffmpeg.exe|Alle Dateien|*.*'
    $dlg.Title = 'ffmpeg.exe auswählen'
    if ($dlg.ShowDialog() -eq 'OK') { $script:Config.ffmpegPath = $dlg.FileName; Save-Config; Sync-SettingsToControls; $lblStatus.Text = 'FFmpeg-Pfad gespeichert.' }
}

function Download-FFmpeg {
    try {
        Ensure-Directory $script:BinDir
        $tmp = Join-Path $env:TEMP ('ffmpeg_download_' + [Guid]::NewGuid().ToString())
        Ensure-Directory $tmp
        $zip = Join-Path $tmp 'ffmpeg.zip'
        $urls = @('https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip','https://github.com/GyanD/codexffmpeg/releases/latest/download/ffmpeg-release-essentials.zip')
        $downloaded = $false
        foreach ($url in $urls) {
            try { $lblStatus.Text = 'FFmpeg wird heruntergeladen …'; $form.Refresh(); Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -ErrorAction Stop; $downloaded = $true; break }
            catch { Write-Log "Download fehlgeschlagen: $url / $($_.Exception.Message)" }
        }
        if (-not $downloaded) { throw 'FFmpeg konnte nicht heruntergeladen werden.' }
        $extract = Join-Path $tmp 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $ff = Get-ChildItem -LiteralPath $extract -Recurse -Filter ffmpeg.exe | Select-Object -First 1
        if (-not $ff) { throw 'Im heruntergeladenen Archiv wurde keine ffmpeg.exe gefunden.' }
        $target = Join-Path $script:BinDir 'ffmpeg.exe'
        Copy-Item -LiteralPath $ff.FullName -Destination $target -Force
        $script:Config.ffmpegPath = $target
        Save-Config; Sync-SettingsToControls
        $lblStatus.Text = 'FFmpeg wurde installiert.'
        [System.Windows.Forms.MessageBox]::Show("FFmpeg wurde installiert:`r`n`r`n$target", 'FFmpeg installiert', 'OK', 'Information') | Out-Null
    } catch {
        Write-Log "FFmpeg-Downloadfehler: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("FFmpeg konnte nicht automatisch installiert werden.`r`n`r`n$($_.Exception.Message)", 'Downloadfehler', 'OK', 'Error') | Out-Null
    }
}

function Get-SourceFromSettingsCheckboxes {
    $mic = [bool]$chkMicSource.Checked
    $sys = [bool]$chkSystemSource.Checked

    if (-not $mic -and -not $sys) {
        # Es muss mindestens eine Quelle aktiv sein. Standard bleibt System-Sound.
        $script:SyncingSettings = $true
        $chkSystemSource.Checked = $true
        $script:SyncingSettings = $false
        $sys = $true
    }

    if ($mic -and $sys) { return 'System-Sound + Mikrofon' }
    if ($mic) { return 'Mikrofon' }
    return 'System-Sound'
}


function Update-FormatQualityState {
    try {
        if (-not $cmbFormat -or -not $cmbQuality) { return }
        $isWav = ([string]$cmbFormat.SelectedItem -eq 'WAV')
        $cmbQuality.Enabled = -not $isWav
        if ($isWav) {
            $cmbQuality.BackColor = [System.Drawing.Color]::FromArgb(235,235,235)
        } else {
            $cmbQuality.BackColor = [System.Drawing.Color]::White
        }
    } catch {}
}

function Apply-AlwaysOnTopSetting {
    try {
        if ($form) { $form.TopMost = [bool]$script:Config.alwaysOnTop }
        Write-Log "Vordergrund-Modus: $($script:Config.alwaysOnTop)"
    } catch { Write-Log "Vordergrund-Modus konnte nicht gesetzt werden: $($_.Exception.Message)" }
}

function Save-SettingsFromControls {
    if ($script:SyncingSettings) { return }
    if ($chkMicSource -and $chkSystemSource) { $script:Config.source = Get-SourceFromSettingsCheckboxes }
    if ($cmbFormat.SelectedItem) { $script:Config.format = [string]$cmbFormat.SelectedItem }
    if ($cmbQuality.SelectedItem) { $script:Config.quality = [string]$cmbQuality.SelectedItem }
    if ($cmbMicDevice -and $cmbMicDevice.SelectedItem) { $script:Config.microphoneDevice = [string]$cmbMicDevice.SelectedItem }
    Update-FormatQualityState
    $script:Config.autoSave = [bool]$chkAutoSave.Checked
    $script:Config.showFileAfterRecording = [bool]$chkShowAfter.Checked
    $script:Config.debugMode = [bool]$chkDebug.Checked
    if ($chkAlwaysOnTop) { $script:Config.alwaysOnTop = [bool]$chkAlwaysOnTop.Checked; Apply-AlwaysOnTopSetting }
    Save-Config
    Sync-StatusIcons
}

function Sync-SettingsToControls {
    $script:SyncingSettings = $true
    try {
        if ($txtOutput) { $txtOutput.Text = $script:Config.outputDir }
        if ($txtWebUrl) { $txtWebUrl.Text = [string]$script:Config.webUrl }
        if ($lblFFmpeg) {
            $lblFFmpeg.Text = 'Native C# / WASAPI Loopback'
            $lblFFmpeg.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        if ($chkMicSource -and $chkSystemSource) {
            $chkMicSource.Checked = ($script:Config.source -eq 'Mikrofon' -or $script:Config.source -eq 'System-Sound + Mikrofon')
            $chkSystemSource.Checked = ($script:Config.source -eq 'System-Sound' -or $script:Config.source -eq 'System-Sound + Mikrofon')
            if (-not $chkMicSource.Checked -and -not $chkSystemSource.Checked) { $chkSystemSource.Checked = $true }
        }
        if ($cmbFormat) { $cmbFormat.SelectedItem = $script:Config.format }
        if ($cmbQuality) { $cmbQuality.SelectedItem = $script:Config.quality }
        if ($cmbMicDevice) { if (-not $cmbMicDevice.Items.Contains($script:Config.microphoneDevice)) { [void]$cmbMicDevice.Items.Add($script:Config.microphoneDevice) }; $cmbMicDevice.SelectedItem = $script:Config.microphoneDevice }
        Update-FormatQualityState
        if ($chkAutoSave) { $chkAutoSave.Checked = [bool]$script:Config.autoSave }
        if ($chkShowAfter) { $chkShowAfter.Checked = [bool]$script:Config.showFileAfterRecording }
        if ($chkDebug) { $chkDebug.Checked = [bool]$script:Config.debugMode }
        if ($chkAlwaysOnTop) { $chkAlwaysOnTop.Checked = [bool]$script:Config.alwaysOnTop }
        Apply-AlwaysOnTopSetting
    } finally {
        $script:SyncingSettings = $false
    }
    Sync-StatusIcons
}

function Sync-StatusIcons {
    $micActive = ($script:Config.source -eq 'Mikrofon' -or $script:Config.source -eq 'System-Sound + Mikrofon')
    $sysActive = ($script:Config.source -eq 'System-Sound' -or $script:Config.source -eq 'System-Sound + Mikrofon')

    try {
        if (Get-Variable -Name lblMicTop -ErrorAction SilentlyContinue) {
            $lblMicTop.ForeColor = if ($micActive) { [System.Drawing.Color]::LimeGreen } else { [System.Drawing.Color]::FromArgb(70,110,70) }
        }
        if (Get-Variable -Name lblSystemTop -ErrorAction SilentlyContinue) {
            $lblSystemTop.ForeColor = if ($sysActive) { [System.Drawing.Color]::LimeGreen } else { [System.Drawing.Color]::FromArgb(70,110,70) }
        }
        if (Get-Variable -Name picMic -ErrorAction SilentlyContinue) {
            $picMic.Visible = $true
            $picMic.BackColor = [System.Drawing.Color]::Black
            $picMic.Enabled = $true
        }
        if (Get-Variable -Name picSpeaker -ErrorAction SilentlyContinue) {
            $picSpeaker.Visible = $true
            $picSpeaker.BackColor = [System.Drawing.Color]::Black
            $picSpeaker.Enabled = $sysActive
        }
        if (Get-Variable -Name micVisualizer -ErrorAction SilentlyContinue) { $micVisualizer.Invalidate() }
        if (Get-Variable -Name systemVisualizer -ErrorAction SilentlyContinue) { $systemVisualizer.Invalidate() }
    } catch {}
}

$script:IsApplyingWindowBounds = $false

function Get-IntConfigValue {
    param([string]$Name, [int]$Default)
    try {
        $v = $script:Config[$Name]
        if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return $Default }
        return [int]$v
    } catch { return $Default }
}

function Get-AnchorWorkArea {
    param([int]$Left, [int]$Bottom)
    try {
        if ($Left -gt -32000 -and $Bottom -gt -32000) {
            $pt = New-Object System.Drawing.Point($Left, [Math]::Max(0, $Bottom - 1))
            return [System.Windows.Forms.Screen]::FromPoint($pt).WorkingArea
        }
    } catch {}
    return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
}

function Save-WindowPlacement {
    try {
        if ($script:IsApplyingWindowBounds -or -not $form) { return }
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
        $script:Config.windowLeft = [int]$form.Left
        $script:Config.windowBottom = [int]$form.Bottom
        $script:Config.windowWidth = [int]$form.Width
        Save-Config
        Write-Log "Fensterposition gespeichert: Left=$($form.Left), Bottom=$($form.Bottom), Width=$($form.Width), Height=$($form.Height)"
    } catch { Write-Log "Fensterposition konnte nicht gespeichert werden: $($_.Exception.Message)" }
}

function Set-AppWindowSize {
    param([int]$Width, [int]$Height)

    # Wichtig: Beim Umschalten zwischen Standard/Dateien/Einstellung bleibt die untere linke Ecke stehen.
    # Dadurch klappt die GUI nur nach oben auf und springt nicht mehr nach links/rechts/oben/unten.
    try {
        $savedLeft = Get-IntConfigValue 'windowLeft' ([int]::MinValue)
        $savedBottom = Get-IntConfigValue 'windowBottom' ([int]::MinValue)
        $savedWidth = Get-IntConfigValue 'windowWidth' $Width

        if ($form -and $form.Width -gt 100) { $targetWidth = [int]$form.Width }
        elseif ($savedWidth -gt 100) { $targetWidth = [int]$savedWidth }
        else { $targetWidth = [int]$Width }

        $screen = if ($savedLeft -ne [int]::MinValue -and $savedBottom -ne [int]::MinValue) {
            Get-AnchorWorkArea $savedLeft $savedBottom
        } elseif ($form -and $form.Left -gt -32000) {
            Get-AnchorWorkArea $form.Left $form.Bottom
        } else {
            [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        }

        if ($targetWidth -lt 540) { $targetWidth = 540 }
        if ($targetWidth -gt [int]($screen.Width * 0.65)) { $targetWidth = [int]($screen.Width * 0.65) }
        if ($Height -gt [int]($screen.Height * 0.70)) { $Height = [int]($screen.Height * 0.70) }
        if ($Height -lt 135) { $Height = 135 }

        if ($savedLeft -ne [int]::MinValue -and $savedBottom -ne [int]::MinValue) {
            $left = [int]$savedLeft
            $bottom = [int]$savedBottom
        } elseif ($form -and $form.Left -gt -32000 -and $form.Bottom -gt 0) {
            $left = [int]$form.Left
            $bottom = [int]$form.Bottom
        } else {
            $left = [int]($screen.Right - $targetWidth - 12)
            $bottom = [int]($screen.Bottom - 12)
        }

        # Nur korrigieren, falls der gespeicherte Punkt außerhalb des sichtbaren Arbeitsbereichs liegt.
        if ($left -lt $screen.Left) { $left = $screen.Left + 8 }
        if (($left + $targetWidth) -gt $screen.Right) { $left = $screen.Right - $targetWidth - 8 }
        if ($bottom -gt $screen.Bottom) { $bottom = $screen.Bottom - 8 }
        if (($bottom - $Height) -lt $screen.Top) { $bottom = $screen.Top + $Height + 8 }

        $top = $bottom - $Height

        $script:IsApplyingWindowBounds = $true
        $form.Size = New-Object System.Drawing.Size($targetWidth, $Height)
        $form.Location = New-Object System.Drawing.Point($left, $top)
        Update-ContentPanelBounds
        $script:IsApplyingWindowBounds = $false

        $script:Config.windowLeft = [int]$left
        $script:Config.windowBottom = [int]$bottom
        $script:Config.windowWidth = [int]$targetWidth
        Save-Config
        Write-Log "Fenster gesetzt: View=$script:CurrentView, Left=$left, Bottom=$bottom, Width=$targetWidth, Height=$Height"
    } catch {
        $script:IsApplyingWindowBounds = $false
        Write-Log "Fenstergröße/Position konnte nicht gesetzt werden: $($_.Exception.Message)"
    }
}



function Update-ContentPanelBounds {
    # Der Zusatzbereich darf nicht als Dock=Fill hinter Recorder/Toolbar liegen.
    # Fester Bezug: oberer Rand = Recorder-Bereich + Toolbar; unterer Rand = Statuszeile.
    try {
        if (-not $form -or -not $contentPanel) { return }
        $top = 0
        if ($header -and $header.Visible) { $top += [int]$header.Height }
        if ($recPanel) { $top += [int]$recPanel.Height }
        if ($toolbar) { $top += [int]$toolbar.Height }
        $bottomReserve = 0
        if ($statusPanel -and $statusPanel.Visible) { $bottomReserve = [int]$statusPanel.Height }
        $h = [int]($form.ClientSize.Height - $top - $bottomReserve)
        if ($h -lt 0) { $h = 0 }
        $contentPanel.SetBounds(0, $top, [int]$form.ClientSize.Width, $h)
        try { $contentPanel.PerformLayout() } catch {}
        Write-Log "Zusatzbereich gesetzt: X=0, Y=$top, W=$($form.ClientSize.Width), H=$h, StatusReserve=$bottomReserve"
    } catch {
        Write-Log "Zusatzbereich konnte nicht gesetzt werden: $($_.Exception.Message)"
    }
}

function Ensure-FilesPanelVisible {
    try {
        $contentPanel.Visible = $true
        $filesPanel.Visible = $true
        $settingsPanel.Visible = $false
        $settingsPanel.SendToBack()
        $filesPanel.BringToFront()
        $actionPanel.BringToFront()
        $grid.Visible = $true
        $grid.BringToFront()
        $grid.ColumnHeadersVisible = $true
        $grid.Invalidate()
        $filesPanel.PerformLayout()
        $contentPanel.PerformLayout()
        Write-Log "Dateiliste sichtbar gesetzt: GridVisible=$($grid.Visible), GridRows=$($grid.Rows.Count), FilesPanelVisible=$($filesPanel.Visible), SettingsPanelVisible=$($settingsPanel.Visible)."
    } catch {
        Write-Log "Dateiliste sichtbar setzen fehlgeschlagen: $($_.Exception.Message)"
    }
}

function Show-View {
    param([string]$View)
    $script:CurrentView = $View
    $filesPanel.Visible = $false
    $settingsPanel.Visible = $false
    $contentPanel.Visible = $false
    $statusPanel.Visible = $false
    switch ($View) {
        'Files' {
            $contentPanel.Visible = $true
            $statusPanel.Visible = $true
            $settingsPanel.Visible = $false
            $filesPanel.Visible = $true
            Set-AppWindowSize 620 360
            Update-ContentPanelBounds
            Refresh-Grid
            Ensure-FilesPanelVisible
        }
        'Settings' {
            $contentPanel.Visible = $true
            $statusPanel.Visible = $true
            $filesPanel.Visible = $false
            $settingsPanel.Visible = $true
            $filesPanel.SendToBack()
            $settingsPanel.BringToFront()
            try {
                $settingsPanel.Location = New-Object System.Drawing.Point(0,0)
                $settingsPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
                $settingsPanel.PerformLayout()
                Write-Log "Einstellungen sichtbar gesetzt: PanelLocation=$($settingsPanel.Location), Size=$($settingsPanel.Size)."
            } catch { Write-Log "Einstellungen sichtbar setzen fehlgeschlagen: $($_.Exception.Message)" }
            Set-AppWindowSize 560 420
            Update-ContentPanelBounds
            try {
                $settingsPanel.Location = New-Object System.Drawing.Point(0,0)
                $settingsPanel.PerformLayout()
            } catch {}
            Sync-SettingsToControls
        }
        default {
            $filesPanel.Visible = $false
            $settingsPanel.Visible = $false
            $filesPanel.SendToBack()
            $settingsPanel.SendToBack()
            Set-AppWindowSize 560 145
            Update-ContentPanelBounds
        }
    }
    Update-ToolbarStates
}

try { Add-NativeWasapiType; Write-Log 'Native C# WASAPI-Komponente bereit.' } catch { Write-Log ('Native C# WASAPI-Komponente konnte nicht geladen werden: ' + $_.Exception.Message); [System.Windows.Forms.MessageBox]::Show(('Native Aufnahme-Komponente konnte nicht geladen werden.`r`n`r`n' + $_.Exception.Message), 'Startfehler', 'OK', 'Error') | Out-Null }

Load-Config
Write-Log "Startart: $script:LauncherKind; ActivePath=$ActivePath; InactivePath=$InactivePath; LauncherLog=$LauncherLogPath; SC-Version=$SpeedCommanderVersion"
if (-not [string]::IsNullOrWhiteSpace($SpeedCommanderExe)) {
    try {
        if (Test-Path -LiteralPath $SpeedCommanderExe) {
            $script:Config.speedCommanderExe = $SpeedCommanderExe
            Write-Log "SpeedCommander-Pfad aus Starter uebernommen: $SpeedCommanderExe"
        } else {
            Write-Log "SpeedCommander-Pfad aus Starter existiert nicht: $SpeedCommanderExe"
        }
    } catch {
        Write-Log "SpeedCommander-Pfad konnte nicht uebernommen werden: $($_.Exception.Message)"
    }
}
Save-Config
Load-Recordings

[void][System.Windows.Forms.Application]::EnableVisualStyles()

# ================= GUI =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Systemton Recorder $script:AppVersion"
$form.StartPosition = 'Manual'
$form.Size = New-Object System.Drawing.Size(560, 145)
$form.MinimumSize = New-Object System.Drawing.Size(540, 135)
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.KeyPreview = $true
try {
    $ico = Asset-Path 'app.ico'
    if (Test-Path -LiteralPath $ico) {
        $appIcon = New-Object System.Drawing.Icon($ico)
        $form.Icon = $appIcon
        $form.ShowIcon = $true
        $form.ShowInTaskbar = $true
    }
} catch { Write-Log "App-Icon konnte nicht gesetzt werden: $($_.Exception.Message)" }

# Kopfzeile
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 0
$header.Visible = $false
$header.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($header)

$picApp = New-Object System.Windows.Forms.PictureBox
$picApp.Location = New-Object System.Drawing.Point(6, 3)
$picApp.Size = New-Object System.Drawing.Size(18, 18)
$picApp.SizeMode = 'StretchImage'
try { $picApp.Image = [System.Drawing.Icon]::ExtractAssociatedIcon((Asset-Path 'app.ico')).ToBitmap() } catch {}
$header.Controls.Add($picApp)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Systemton Recorder v1.51.0 | Native Aufnahme'
$titleLabel.ForeColor = [System.Drawing.Color]::WhiteSmoke
$titleLabel.Font = New-Object System.Drawing.Font('Georgia', 8.2, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(30, 4)
$titleLabel.Size = New-Object System.Drawing.Size(420, 18)
$header.Controls.Add($titleLabel)

$winHint = New-Object System.Windows.Forms.Label
$winHint.Text = '–    ×'
$winHint.ForeColor = [System.Drawing.Color]::WhiteSmoke
$winHint.Anchor = 'Top,Right'
$winHint.TextAlign = 'MiddleRight'
$winHint.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$winHint.Location = New-Object System.Drawing.Point(450, 1)
$winHint.Size = New-Object System.Drawing.Size(60, 22)
$header.Controls.Add($winHint)

# Toolbar
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.Height = 36
$toolbar.BackColor = [System.Drawing.Color]::FromArgb(224,232,239)
$form.Controls.Add($toolbar)


function New-BuiltinToolbarIcon {
    param([string]$IconName)
    $bmp = New-Object System.Drawing.Bitmap(16,16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $blue = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(55,150,215))
    $gray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165,170,175))
    $dark = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,90,100), 1.2)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    try {
        switch -Regex ($IconName) {
            'start|pause' {
                $g.FillRectangle($blue, 1,1,14,14)
                $pts = @((New-Object System.Drawing.Point(5,3)),(New-Object System.Drawing.Point(12,8)),(New-Object System.Drawing.Point(5,13)))
                $g.FillPolygon($white, $pts)
                $g.FillRectangle($white, 2,3,2,10)
                break
            }
            'stop|beenden' {
                $g.FillRectangle($gray, 2,2,12,12)
                $g.DrawRectangle($dark, 2,2,12,12)
                break
            }
            'files|dateien' {
                $g.FillRectangle($gray, 4,2,8,12)
                $g.DrawRectangle($dark, 4,2,8,12)
                $g.DrawLine($dark, 6,5,11,5)
                $g.DrawLine($dark, 6,8,11,8)
                $g.DrawLine($dark, 6,11,10,11)
                break
            }
            'setting|einstellung' {
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,95,255), 1.7)
                $g.DrawEllipse($pen, 4,4,8,8)
                for ($i=0; $i -lt 8; $i++) {
                    $a = $i * [Math]::PI / 4
                    $x1 = 8 + [Math]::Cos($a) * 5
                    $y1 = 8 + [Math]::Sin($a) * 5
                    $x2 = 8 + [Math]::Cos($a) * 7
                    $y2 = 8 + [Math]::Sin($a) * 7
                    $g.DrawLine($pen, [float]$x1, [float]$y1, [float]$x2, [float]$y2)
                }
                $pen.Dispose()
                break
            }
            default {
                $g.FillEllipse($blue,2,2,12,12)
                break
            }
        }
    } finally {
        $g.Dispose(); $blue.Dispose(); $gray.Dispose(); $dark.Dispose(); $white.Dispose()
    }
    return $bmp
}

function New-ToolbarIcon {
    param(
        [string]$IconName,
        [int]$Size = 18,
        [int]$RightPadding = 0
    )
    # Bei Toolbar-Icons kann IconName schon ein Dateiname sein; SVG-Cache wird ueber die aufrufenden Icon-Keys erzeugt.
    $img = Load-ImageSafe $IconName
    if (-not $img) { $img = New-BuiltinToolbarIcon $IconName }
    if (-not $img) { return $null }

    # Quadratisches Icon ohne künstliche rechte Polster-Leinwand.
    # Der Abstand zum Text wird im eigenen Toolbar-Control gezeichnet.
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, 0, 0, $Size, $Size)
    $g.Dispose()
    try { $img.Dispose() } catch {}
    return $bmp
}

function Get-ToolbarBaseColor {
    param([string]$Name)
    if ($Name -eq 'Files' -and $script:CurrentView -eq 'Files') { return [System.Drawing.Color]::FromArgb(190,215,235) }
    if ($Name -eq 'Settings' -and $script:CurrentView -eq 'Settings') { return [System.Drawing.Color]::FromArgb(190,215,235) }
    if ($Name -eq 'Start') {
        if ($script:IsRecording -and $script:IsPaused) { return [System.Drawing.Color]::FromArgb(248,232,170) }
        if ($script:IsRecording) { return [System.Drawing.Color]::FromArgb(198,232,205) }
    }
    return [System.Drawing.Color]::FromArgb(224,232,239)
}

function New-ToolbarButton {
    param([string]$Text, [string]$IconName, [int]$X, [int]$W, [string]$StateName)

    # Eigener Button-Control statt normalem WinForms-Button:
    # Damit gibt es keinen Fokusrahmen, keinen schwarzen Rahmen und keinen blauen Klickrahmen.
    $b = New-Object RecorderToolbarButton
    $b.Text = $Text
    $b.Tag = $StateName
    $b.Location = New-Object System.Drawing.Point($X, 4)
    $b.Size = New-Object System.Drawing.Size($W, 28)
    $b.BackColor = [System.Drawing.Color]::FromArgb(224,232,239)
    $b.NormalBackColor = [System.Drawing.Color]::FromArgb(224,232,239)
    $b.HoverBackColor = [System.Drawing.Color]::FromArgb(204,222,238)
    $b.DownBackColor = [System.Drawing.Color]::FromArgb(175,205,230)
    $b.Margin = New-Object System.Windows.Forms.Padding(0)
    $b.TabStop = $false
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.2, [System.Drawing.FontStyle]::Bold)
    $b.ForeColor = [System.Drawing.Color]::Black

    $img = New-ToolbarIcon $IconName 18 0
    if ($img) { $b.Image = $img }

    $toolbar.Controls.Add($b)
    return $b
}

function Set-ToolbarButtonIcon {
    param(
        $Button,
        [string]$IconKey,
        [string]$DefaultFile
    )
    if (-not $Button) { return }
    try {
        $file = Get-IconFile $IconKey $DefaultFile
        $img = New-ToolbarIcon $file 18 0
        if ($img) {
            try { if ($Button.Image) { $Button.Image.Dispose() } } catch {}
            $Button.Image = $img
            $Button.Invalidate()
        }
    } catch { Write-Log "Toolbar-Icon konnte nicht gesetzt werden: $IconKey -> $($_.Exception.Message)" }
}

function Set-ToolbarButtonBackColor {
    param($Button, [System.Drawing.Color]$Color)
    if (-not $Button) { return }
    $Button.BackColor = $Color
    if ($Button.PSObject.Properties.Name -contains 'NormalBackColor') {
        $Button.NormalBackColor = $Color
    }
    try { $Button.Invalidate() } catch {}
}

function Update-ToolbarStates {
    Set-ToolbarButtonBackColor $btnStartPause (Get-ToolbarBaseColor 'Start')
    Set-ToolbarButtonBackColor $btnFiles (Get-ToolbarBaseColor 'Files')
    Set-ToolbarButtonBackColor $btnSettings (Get-ToolbarBaseColor 'Settings')
    Set-ToolbarButtonBackColor $btnStop ([System.Drawing.Color]::FromArgb(224,232,239))
}

$btnStartPause = New-ToolbarButton 'Start' (Get-IconFile 'start' 'icon_start.png') 10 96 'Start'
$btnStop       = New-ToolbarButton 'Stop' (Get-IconFile 'stop' 'icon_stop.png') 118 86 'Stop'

$sep1 = New-Object System.Windows.Forms.Label
$sep1.BorderStyle = 'Fixed3D'
$sep1.Location = New-Object System.Drawing.Point(218, 6)
$sep1.Size = New-Object System.Drawing.Size(2, 24)
$toolbar.Controls.Add($sep1)

$btnFiles    = New-ToolbarButton 'Dateien' (Get-IconFile 'files' 'icon_files.png') 234 122 'Files'
$btnSettings = New-ToolbarButton 'Einstellung' (Get-IconFile 'settings' 'icon_settings.png') 366 158 'Settings'

# Recorder-Bereich
$recPanel = New-Object System.Windows.Forms.Panel
$recPanel.Dock = 'Top'
$recPanel.Height = 74
$recPanel.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($recPanel)

$lblMicTop = New-Object System.Windows.Forms.Label
$lblMicTop.Text = 'Mikrofon'
$lblMicTop.ForeColor = [System.Drawing.Color]::LimeGreen
$lblMicTop.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
$lblMicTop.TextAlign = 'MiddleCenter'
$lblMicTop.Location = New-Object System.Drawing.Point(18, 7)
$lblMicTop.Size = New-Object System.Drawing.Size(150, 22)
$recPanel.Controls.Add($lblMicTop)

$picMic = New-Object System.Windows.Forms.PictureBox
$picMic.Location = New-Object System.Drawing.Point(78, 28)
$picMic.Size = New-Object System.Drawing.Size(28, 28)
$picMic.SizeMode = 'Zoom'
$picMic.BackColor = [System.Drawing.Color]::Black
$picMic.Image = Load-ConfiguredIconImage 'microphone' 'icon_microphone.png' 28
if (-not $picMic.Image) { $picMic.Image = Load-MicrophoneImage }
$recPanel.Controls.Add($picMic)

$micVisualizer = New-Object System.Windows.Forms.Panel
$micVisualizer.Location = New-Object System.Drawing.Point(18, 45)
$micVisualizer.Size = New-Object System.Drawing.Size(150, 25)
$micVisualizer.BackColor = [System.Drawing.Color]::Black
$recPanel.Controls.Add($micVisualizer)

$lblSystemTop = New-Object System.Windows.Forms.Label
$lblSystemTop.Text = 'System-Sound'
$lblSystemTop.ForeColor = [System.Drawing.Color]::LimeGreen
$lblSystemTop.Font = New-Object System.Drawing.Font('Segoe UI', 8.4, [System.Drawing.FontStyle]::Bold)
$lblSystemTop.TextAlign = 'MiddleCenter'
$lblSystemTop.Location = New-Object System.Drawing.Point(185, 7)
$lblSystemTop.Size = New-Object System.Drawing.Size(155, 22)
$recPanel.Controls.Add($lblSystemTop)

$picSpeaker = New-Object System.Windows.Forms.PictureBox
$picSpeaker.Location = New-Object System.Drawing.Point(252, 28)
$picSpeaker.Size = New-Object System.Drawing.Size(24, 24)
$picSpeaker.SizeMode = 'Zoom'
$picSpeaker.BackColor = [System.Drawing.Color]::Black
$picSpeaker.Image = Load-ConfiguredIconImage 'systemSound' 'icon_system_sound.png' 24
$recPanel.Controls.Add($picSpeaker)

$systemVisualizer = New-Object System.Windows.Forms.Panel
$systemVisualizer.Location = New-Object System.Drawing.Point(185, 45)
$systemVisualizer.Size = New-Object System.Drawing.Size(155, 25)
$systemVisualizer.BackColor = [System.Drawing.Color]::Black
$recPanel.Controls.Add($systemVisualizer)

$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Text = '00:00:00'
$lblTime.ForeColor = [System.Drawing.Color]::Red
$lblTime.BackColor = [System.Drawing.Color]::Black
$lblTime.Font = New-Object System.Drawing.Font('Consolas', 24, [System.Drawing.FontStyle]::Bold)
$lblTime.Location = New-Object System.Drawing.Point(340, 18)
$lblTime.Size = New-Object System.Drawing.Size(225, 52)
$lblTime.TextAlign = 'MiddleCenter'
$recPanel.Controls.Add($lblTime)

function Update-RecorderLayout {
    if (-not $recPanel) { return }
    $w = [Math]::Max(560, $recPanel.ClientSize.Width)
    # 1.38.0: Die rote 7-Segment-Zeit braucht mehr Platz als die alte Breite.
    # Sonst wird rechts die letzte Sekundenziffer abgeschnitten.
    $timeW = 225
    $rightPad = 12
    $timeX = $w - $timeW - $rightPad
    if ($timeX -lt 300) { $timeX = 300 }
    $areaW = [Math]::Max(145, [int]($timeX / 2))
    $visW = [Math]::Min(155, $areaW - 24)
    if ($visW -lt 115) { $visW = 115 }
    # Gewünschte Reihenfolge: links System-Sound, rechts Mikrofon.
    $sysX = [int](($areaW - $visW) / 2)
    $micX = $areaW + [int](($areaW - $visW) / 2)

    $lblSystemTop.SetBounds($sysX, 7, $visW, 22)
    $picSpeaker.SetBounds([int]($sysX + ($visW - $picSpeaker.Width) / 2), 28, 24, 24)
    $systemVisualizer.SetBounds($sysX, 45, $visW, 25)

    $lblMicTop.SetBounds($micX, 7, $visW, 22)
    $picMic.SetBounds([int]($micX + ($visW - $picMic.Width) / 2), 28, 28, 28)
    $micVisualizer.SetBounds($micX, 45, $visW, 25)

    $lblTime.SetBounds($timeX, 18, $timeW, 52)
}
$recPanel.Add_Resize({ Update-RecorderLayout })

# Container für Zusatzbereiche
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = 'None'
$contentPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$contentPanel.BackColor = [System.Drawing.Color]::FromArgb(238,238,238)
$contentPanel.Visible = $false
$form.Controls.Add($contentPanel)

# Dateiliste
$filesPanel = New-Object System.Windows.Forms.Panel
$filesPanel.Dock = 'Fill'
$filesPanel.BackColor = [System.Drawing.Color]::FromArgb(238,238,238)
$filesPanel.Visible = $false
$filesPanel.Padding = New-Object System.Windows.Forms.Padding(0,0,0,0)
$contentPanel.Controls.Add($filesPanel)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.RowHeadersVisible = $false
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.GridColor = [System.Drawing.Color]::FromArgb(225,225,225)
$grid.BorderStyle = 'Fixed3D'
$grid.ColumnHeadersVisible = $true
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 8.2, [System.Drawing.FontStyle]::Regular)
$grid.ColumnHeadersHeight = 26
$grid.AutoSizeRowsMode = 'None'
$grid.RowTemplate.Height = 21
[void]$grid.Columns.Add('StatusIcon','')
[void]$grid.Columns.Add('Dateiname','Dateiname')
[void]$grid.Columns.Add('Dauer','Dauer')
[void]$grid.Columns.Add('Groesse','Größe')
[void]$grid.Columns.Add('Format','Format')
[void]$grid.Columns.Add('Erstellt','Erstellt')
[void]$grid.Columns.Add('Nummer','#')
[void]$grid.Columns.Add('Pfad','Pfad')
$grid.Columns['StatusIcon'].Width = 26
$grid.Columns['Dateiname'].Width = 160
$grid.Columns['Dauer'].Width = 72
$grid.Columns['Groesse'].Width = 78
$grid.Columns['Format'].Width = 58
$grid.Columns['Erstellt'].Width = 128
$grid.Columns['Nummer'].Width = 42
$grid.Columns['Pfad'].AutoSizeMode = 'Fill'
foreach ($col in $grid.Columns) { $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Programmatic }
$grid.Add_ColumnHeaderMouseClick({ param($sender, $e) Sort-GridByColumn $e.ColumnIndex })

$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Dock = 'Bottom'
$actionPanel.Height = 40
$actionPanel.BackColor = [System.Drawing.Color]::FromArgb(238,238,238)
$filesPanel.Controls.Add($actionPanel)

# Wichtig: erst die untere Aktionsleiste docken, danach die Tabelle als Fill einhängen.
# Sonst kann die Tabelle je nach WinForms-ZOrder hinter anderen Flächen liegen oder unsichtbar wirken.
$filesPanel.Controls.Add($grid)
$grid.BringToFront()

function Get-ActionButtonImage {
    param([string]$IconName, [int]$Size = 20)
    if ([string]::IsNullOrWhiteSpace($IconName)) { return $null }
    $p = Resolve-ConfigIconPath $IconName
    try {
        if (Test-Path -LiteralPath $p) {
            if ([IO.Path]::GetExtension($p).ToLowerInvariant() -eq '.ico') {
                $ico = New-Object System.Drawing.Icon($p)
                $src = $ico.ToBitmap()
                $ico.Dispose()
            } else {
                $src = [System.Drawing.Image]::FromFile($p)
            }
            $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.DrawImage($src, 0, 0, $Size, $Size)
            $g.Dispose()
            try { $src.Dispose() } catch {}
            return $bmp
        }
    } catch { Write-Log "Action-Icon konnte nicht geladen werden: $IconName -> $($_.Exception.Message)" }
    return $null
}

$actionTip = New-Object System.Windows.Forms.ToolTip
try {
    $actionTip.InitialDelay = 700
    $actionTip.ReshowDelay = 120
    $actionTip.AutoPopDelay = 12000
    $actionTip.ShowAlways = $true
} catch {}

function New-ActionButton {
    param(
        [string]$Symbol,
        [int]$X,
        [string]$ToolTipText,
        [string]$IconName = ''
    )
    # Kein echter Button mehr: Label/PictureBox-artiges Element, damit Windows keinen Fokus-/Rahmen zeichnet.
    $b = New-Object System.Windows.Forms.Label
    $b.Text = $Symbol
    $b.Location = New-Object System.Drawing.Point($X, 6)
    $b.Size = New-Object System.Drawing.Size(42, 27)
    $b.TabStop = $false
    $b.UseMnemonic = $false
    $b.BackColor = [System.Drawing.Color]::FromArgb(238,238,238)
    $b.TextAlign = 'MiddleCenter'
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 13.0, [System.Drawing.FontStyle]::Regular)
    $img = Get-ActionButtonImage $IconName 24
    if ($img) {
        $b.Image = $img
        $b.Text = ''
        $b.ImageAlign = 'MiddleCenter'
    }
    try { $actionTip.SetToolTip($b, $ToolTipText) } catch {}
    $actionPanel.Controls.Add($b)
    return $b
}

# Reduzierte Aktionsleiste: Symbole und Anzeigenamen kommen aus recorder-config.json.
# Dadurch können Icon-Pfad, Dateiname, Tooltip-Name und Tastenkürzel angepasst oder übersetzt werden.
$btnJump   = New-ActionButton '' 20  (Get-ActionButtonTipText 'openFile' 'Zu Datei' 'Strg+Q' 'in SpeedCommander/Explorer springen') (Get-ActionIconSetting 'openFile' 'file' 'icon_folder.png')
$btnDelete = New-ActionButton '' 80  (Get-ActionButtonTipText 'delete' 'Aufnahme loeschen' 'Strg+L') (Get-ActionIconSetting 'delete' 'file' 'icon_garbage.png')
$btnRename = New-ActionButton '' 140 (Get-ActionButtonTipText 'rename' 'Aufnahme umbenennen' 'Strg+U') (Get-ActionIconSetting 'rename' 'file' 'icon_rename.png')
$btnPlay   = New-ActionButton '' 200 (Get-ActionButtonTipText 'play' 'Aufnahme abspielen' 'Strg+P') (Get-ActionIconSetting 'play' 'file' 'icon_play.png')
try { $actionPanel.BringToFront(); $grid.Visible = $true; $grid.BringToFront(); $actionPanel.BringToFront() } catch {}

# Einstellungen
$settingsPanel = New-Object System.Windows.Forms.Panel
$settingsPanel.Dock = 'Fill'
$settingsPanel.BackColor = [System.Drawing.Color]::FromArgb(238,238,238)
$settingsPanel.Visible = $false
$settingsPanel.Padding = New-Object System.Windows.Forms.Padding(0)
$settingsPanel.AutoScroll = $false
$contentPanel.Controls.Add($settingsPanel)

function New-FlatSmallButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 23)
    # Label statt Button: absolut rahmenlos, kein Fokusrahmen, trotzdem klickbar.
    $b = New-Object System.Windows.Forms.Label
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.TabStop = $false
    $b.UseMnemonic = $false
    $b.TextAlign = 'MiddleCenter'
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.BackColor = [System.Drawing.Color]::FromArgb(224,232,239)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.0)
    $settingsPanel.Controls.Add($b)
    return $b
}

function New-SettingsLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 82)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 20)
    $l.TextAlign = 'MiddleLeft'
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
    $settingsPanel.Controls.Add($l)
    return $l
}

function New-SettingsCombo {
    param([int]$X, [int]$Y, [int]$W, [object[]]$Items)
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size = New-Object System.Drawing.Size($W, 22)
    $c.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
    [void]$c.Items.AddRange($Items)
    $settingsPanel.Controls.Add($c)
    return $c
}

# Zeile 1: Speicherordner wie im Referenzbild
$lblFolder = New-SettingsLabel 'Speicherordner:' 18 188 104
$lblFolder.TextAlign = 'MiddleRight'

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(126, 186)
$txtOutput.Size = New-Object System.Drawing.Size(300, 22)
$txtOutput.ReadOnly = $false
$txtOutput.BorderStyle = 'FixedSingle'
$txtOutput.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$settingsPanel.Controls.Add($txtOutput)

$btnBrowse = New-FlatSmallButton '' 434 184 42 26
$btnBrowse.Image = Load-ConfiguredIconImage 'folder' 'icon_folder.png' 22
$btnBrowse.ImageAlign = 'MiddleCenter'
$btnBrowse.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 12.0, [System.Drawing.FontStyle]::Regular)

$lblWebUrl = New-SettingsLabel 'Webseite:' 18 218 104
$lblWebUrl.TextAlign = 'MiddleRight'

$txtWebUrl = New-Object System.Windows.Forms.TextBox
$txtWebUrl.Location = New-Object System.Drawing.Point(126, 216)
$txtWebUrl.Size = New-Object System.Drawing.Size(300, 22)
$txtWebUrl.ReadOnly = $false
$txtWebUrl.BorderStyle = 'FixedSingle'
$txtWebUrl.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$settingsPanel.Controls.Add($txtWebUrl)

$btnOpenWeb = New-FlatSmallButton '' 434 214 42 26
$btnOpenWeb.Image = Load-ConfiguredIconImage 'web' 'icon_web.png' 22
$btnOpenWeb.ImageAlign = 'MiddleCenter'
$btnOpenWeb.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 12.0, [System.Drawing.FontStyle]::Regular)

# Zeile 2: FFmpeg-Pfad und Aktionen
$lblFFmpegTitle = New-SettingsLabel 'Aufnahme:' 18 53 62
$lblFFmpegTitle.Visible = $false

$lblFFmpeg = New-Object System.Windows.Forms.Label
$lblFFmpeg.Text = 'nicht geprüft'
$lblFFmpeg.Location = New-Object System.Drawing.Point(82, 53)
$lblFFmpeg.Size = New-Object System.Drawing.Size(246, 20)
$lblFFmpeg.AutoEllipsis = $true
$lblFFmpeg.Font = New-Object System.Drawing.Font('Segoe UI', 8.0)
$settingsPanel.Controls.Add($lblFFmpeg)
$lblFFmpeg.Visible = $false

$btnChooseFF = New-FlatSmallButton 'Native Aufnahme aktiv' 338 49 204 26
$btnChooseFF.Visible = $false
$btnDownloadFF = New-FlatSmallButton 'FFmpeg nicht benötigt' 338 82 204 27
$btnDownloadFF.Visible = $false

# Trennlinie
$line = New-Object System.Windows.Forms.Label
$line.BorderStyle = 'Fixed3D'
$line.Location = New-Object System.Drawing.Point(18, 174)
$line.Size = New-Object System.Drawing.Size(524, 2)
$settingsPanel.Controls.Add($line)

# Audioquelle: bewusst zwei Checkboxen, damit A, B oder A+B möglich ist.
$lblAudioSource = New-SettingsLabel 'Audioquelle:' 18 18 94
$lblAudioSource.Font = New-Object System.Drawing.Font('Segoe UI', 8.6, [System.Drawing.FontStyle]::Bold)

$chkSystemSource = New-Object System.Windows.Forms.CheckBox
$chkSystemSource.Text = 'System-Sound'
$chkSystemSource.Location = New-Object System.Drawing.Point(42, 42)
$chkSystemSource.Size = New-Object System.Drawing.Size(140, 28)
$chkSystemSource.Font = New-Object System.Drawing.Font('Segoe UI', 9.2, [System.Drawing.FontStyle]::Bold)
$chkSystemSource.TabStop = $false
$settingsPanel.Controls.Add($chkSystemSource)

$chkMicSource = New-Object System.Windows.Forms.CheckBox
$chkMicSource.Text = 'Mikrofon'
$chkMicSource.Location = New-Object System.Drawing.Point(218, 42)
$chkMicSource.Size = New-Object System.Drawing.Size(108, 28)
$chkMicSource.Font = New-Object System.Drawing.Font('Segoe UI', 9.2, [System.Drawing.FontStyle]::Bold)
$chkMicSource.TabStop = $false
$settingsPanel.Controls.Add($chkMicSource)

$lblMicDevice = New-SettingsLabel 'Mikrofon:' 326 46 56
$lblMicDevice.TextAlign = 'MiddleRight'
$cmbMicDevice = New-SettingsCombo 388 42 138 @('Standardmikrofon')

# Format und Qualität bleiben kompakt, aber nicht in die Audioquelle gequetscht.
$lblFormat = New-SettingsLabel 'Format:' 42 84 58
$cmbFormat = New-SettingsCombo 102 80 96 @('MP3','WAV','M4A')

$lblQuality = New-SettingsLabel 'Qualität:' 252 84 62
$cmbQuality = New-SettingsCombo 318 80 112 @('Niedrig','Normal','Hoch')

# Optionen
$chkShowAfter = New-Object System.Windows.Forms.CheckBox
$chkShowAfter.Text = 'Nach Aufnahme in Dateiliste anzeigen'
$chkShowAfter.Location = New-Object System.Drawing.Point(252, 120)
$chkShowAfter.Size = New-Object System.Drawing.Size(285, 22)
$chkShowAfter.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$chkShowAfter.TabStop = $false
$settingsPanel.Controls.Add($chkShowAfter)

$chkAutoSave = New-Object System.Windows.Forms.CheckBox
$chkAutoSave.Text = 'Automatisch speichern'
$chkAutoSave.Location = New-Object System.Drawing.Point(42, 120)
$chkAutoSave.Size = New-Object System.Drawing.Size(175, 22)
$chkAutoSave.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$chkAutoSave.TabStop = $false
$settingsPanel.Controls.Add($chkAutoSave)

$chkDebug = New-Object System.Windows.Forms.CheckBox
$chkDebug.Text = 'Debug-/Diagnosemodus'
$chkDebug.Location = New-Object System.Drawing.Point(42, 150)
$chkDebug.Size = New-Object System.Drawing.Size(170, 22)
$chkDebug.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$chkDebug.TabStop = $false
$settingsPanel.Controls.Add($chkDebug)

$chkAlwaysOnTop = New-Object System.Windows.Forms.CheckBox
$chkAlwaysOnTop.Text = 'Recorder im Vordergrund halten'
$chkAlwaysOnTop.Location = New-Object System.Drawing.Point(252, 150)
$chkAlwaysOnTop.Size = New-Object System.Drawing.Size(220, 22)
$chkAlwaysOnTop.Font = New-Object System.Drawing.Font('Segoe UI', 8.2)
$chkAlwaysOnTop.TabStop = $false
$settingsPanel.Controls.Add($chkAlwaysOnTop)

# Die Audioquelle wird ausschließlich über die beiden Checkboxen gesteuert.
# Eine zusätzliche Klartext-Statuszeile wird bewusst nicht mehr angezeigt.

# Statuszeile
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = 'Bottom'
$statusPanel.Height = 16
$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(240,240,240)
$statusPanel.Visible = $false
$form.Controls.Add($statusPanel)
try { $form.Add_Resize({ Update-ContentPanelBounds }) } catch {}
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Bereit.'
$lblStatus.Location = New-Object System.Drawing.Point(4, 1)
$lblStatus.Size = New-Object System.Drawing.Size(190, 15)
$statusPanel.Controls.Add($lblStatus)
$lblSize = New-Object System.Windows.Forms.Label
$lblSize.Text = ''
$lblSize.Location = New-Object System.Drawing.Point(200, 1)
$lblSize.Size = New-Object System.Drawing.Size(90, 15)
$statusPanel.Controls.Add($lblSize)
$linkTask = New-Object System.Windows.Forms.LinkLabel
$linkTask.Text = 'Keine geplante Aufgabe'
$linkTask.Location = New-Object System.Drawing.Point(300, 1)
$linkTask.Size = New-Object System.Drawing.Size(140, 15)
$linkTask.TabStop = $false
$linkTask.LinkBehavior = [System.Windows.Forms.LinkBehavior]::NeverUnderline
$statusPanel.Controls.Add($linkTask)
$lblVersionBottom = New-Object System.Windows.Forms.Label
$lblVersionBottom.Text = $script:AppVersion
$lblVersionBottom.Anchor = 'Top,Right'
$lblVersionBottom.TextAlign = 'MiddleRight'
$lblVersionBottom.Location = New-Object System.Drawing.Point(440, 1)
$lblVersionBottom.Size = New-Object System.Drawing.Size(70, 14)
$statusPanel.Controls.Add($lblVersionBottom)

# Events
# Hovertexte mit Tastenkombinationen
function Set-ControlHoverTip {
    param(
        [System.Windows.Forms.Control]$Control,
        [string]$Text
    )
    try {
        if ($null -ne $Control -and -not [string]::IsNullOrWhiteSpace($Text)) {
            $actionTip.SetToolTip($Control, $Text)
        }
    } catch {}
}

Set-ControlHoverTip $btnStartPause "Start: Alt+S`r`nPause/Fortsetzen: Leertaste"
Set-ControlHoverTip $btnStop "Stopp: Esc"
Set-ControlHoverTip $btnFiles "Dateien ein-/ausblenden: Strg+D"
Set-ControlHoverTip $btnSettings "Einstellung ein-/ausblenden: Strg+E"

Set-ControlHoverTip $btnJump "Zu Datei in SpeedCommander/Explorer springen: Strg+Q"
Set-ControlHoverTip $btnDelete "Aufnahme löschen: Strg+L"
Set-ControlHoverTip $btnRename "Aufnahme umbenennen: Strg+U"
Set-ControlHoverTip $btnPlay "Aufnahme abspielen: Strg+P"
Set-ControlHoverTip $grid "Dateiliste`r`nSpaltenkopf anklicken = sortieren"

Set-ControlHoverTip $chkSystemSource "System-Sound aufnehmen: Alt+S"
Set-ControlHoverTip $chkMicSource "Mikrofon aufnehmen: Alt+M"
Set-ControlHoverTip $lblMicDevice "Mikrofon-Auswahl: Alt+I"
Set-ControlHoverTip $cmbMicDevice "Mikrofon-Auswahl öffnen: Alt+I"
Set-ControlHoverTip $lblFormat "Format auswählen: Alt+F"
Set-ControlHoverTip $cmbFormat "Format auswählen: Alt+F"
Set-ControlHoverTip $lblQuality "Qualität auswählen: Alt+Q"
Set-ControlHoverTip $cmbQuality "Qualität auswählen: Alt+Q"
Set-ControlHoverTip $chkAutoSave "Automatisch speichern: Alt+A"
Set-ControlHoverTip $chkShowAfter "Nach Aufnahme in Dateiliste anzeigen: Alt+N"
Set-ControlHoverTip $chkDebug "Debug-/Diagnosemodus: Alt+D"
Set-ControlHoverTip $chkAlwaysOnTop "Recorder im Vordergrund halten: Alt+R"
Set-ControlHoverTip $lblFolder "Speicherordner auswählen: Strg+O"
Set-ControlHoverTip $txtOutput "Speicherordner`r`nOrdner wählen: Strg+O"
Set-ControlHoverTip $btnBrowse "Ordner wählen: Strg+O"
Set-ControlHoverTip $lblWebUrl "Webseite-Feld: Alt+W`r`nWebseite öffnen: Strg+Alt+Q"
Set-ControlHoverTip $txtWebUrl "Webseite-Adresse`r`nFeld auswählen: Alt+W`r`nÖffnen: Strg+Alt+Q"
Set-ControlHoverTip $btnOpenWeb "Webseite öffnen: Strg+Alt+Q"

$btnStartPause.Add_Click({ Toggle-StartPause })
$btnStop.Add_Click({ Stop-RecordingOrPlayback })
$btnFiles.Add_Click({ if ($script:CurrentView -eq 'Files') { Show-View 'Standard' } else { Show-View 'Files' } })
$btnSettings.Add_Click({ if ($script:CurrentView -eq 'Settings') { Show-View 'Standard' } else { Show-View 'Settings' } })
$btnBrowse.Add_Click({ Choose-OutputFolder })
$txtOutput.Add_Leave({ Save-OutputFolderFromTextBox })
$btnOpenWeb.Add_Click({ Open-ConfiguredWebsite })
$txtWebUrl.Add_Leave({ Save-WebUrlFromTextBox })

function Test-TextInputFocused {
    try {
        $c = [System.Windows.Forms.Control]::FromHandle([RecorderNativeUser32]::GetFocus())
        if ($null -eq $c) { return $false }
        if ($c -is [System.Windows.Forms.TextBox]) { return $true }
        if ($c -is [System.Windows.Forms.ComboBox]) { return $true }
        return $false
    } catch { return $false }
}

# Kleiner User32-Helfer, damit Leertaste beim Tippen in Textfeldern nicht als Pause/Fortsetzen wirkt.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RecorderNativeUser32 {
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
}
"@ -ErrorAction SilentlyContinue | Out-Null
} catch { }

function Focus-And-DropDown {
    param([System.Windows.Forms.ComboBox]$Combo)
    try {
        if ($script:CurrentView -ne 'Settings') { Show-View 'Settings' }
        $Combo.Focus()
        $Combo.DroppedDown = $true
    } catch { Write-Log "Dropdown-Fokus fehlgeschlagen: $($_.Exception.Message)" }
}

function Toggle-CheckboxShortcut {
    param([System.Windows.Forms.CheckBox]$CheckBox, [string]$Name)
    try {
        if ($script:CurrentView -ne 'Settings') { Show-View 'Settings' }
        $CheckBox.Checked = -not $CheckBox.Checked
        $CheckBox.Focus()
        Write-Log "Tastenkürzel: $Name -> $($CheckBox.Checked)"
    } catch { Write-Log "Tastenkürzel $Name fehlgeschlagen: $($_.Exception.Message)" }
}

function Invoke-RecorderShortcut {
    param([System.Windows.Forms.KeyEventArgs]$e)
    try {
        $handled = $true
        $ctrl = $e.Control
        $alt = $e.Alt
        $shift = $e.Shift
        $key = $e.KeyCode

        if ($ctrl -and $alt -and $key -eq [System.Windows.Forms.Keys]::Q) { Open-ConfiguredWebsite }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::D) { if ($script:CurrentView -eq 'Files') { Show-View 'Standard' } else { Show-View 'Files' } }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::E) { if ($script:CurrentView -eq 'Settings') { Show-View 'Standard' } else { Show-View 'Settings' } }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::Q) { Jump-ToSelectedRecording }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::L) { Delete-SelectedRecording }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::U) { Rename-SelectedRecording }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::P) { Play-SelectedRecording }
        elseif ($ctrl -and -not $alt -and $key -eq [System.Windows.Forms.Keys]::O) { Choose-OutputFolder }
        elseif ($key -eq [System.Windows.Forms.Keys]::Escape) { if ($script:IsRecording) { Stop-Recording } else { Show-View 'Standard' } }
        elseif ($key -eq [System.Windows.Forms.Keys]::Space -and -not (Test-TextInputFocused)) { if ($script:IsRecording) { Toggle-StartPause } else { $handled = $false } }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::S) {
            if ($script:CurrentView -eq 'Settings') { Toggle-CheckboxShortcut $chkSystemSource 'System-Sound' } else { Toggle-StartPause }
        }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::M) { Toggle-CheckboxShortcut $chkMicSource 'Mikrofon' }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::F) { Focus-And-DropDown $cmbFormat }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::Q) { Focus-And-DropDown $cmbQuality }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::A) { Toggle-CheckboxShortcut $chkAutoSave 'Automatisch speichern' }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::N) { Toggle-CheckboxShortcut $chkShowAfter 'Nach Aufnahme in Dateiliste anzeigen' }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::D) { Toggle-CheckboxShortcut $chkDebug 'Debug-/Diagnosemodus' }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::R) { Toggle-CheckboxShortcut $chkAlwaysOnTop 'Recorder im Vordergrund halten' }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::W) {
            if ($script:CurrentView -ne 'Settings') { Show-View 'Settings' }
            $txtWebUrl.Focus()
            $txtWebUrl.SelectAll()
        }
        elseif ($alt -and -not $ctrl -and $key -eq [System.Windows.Forms.Keys]::I) { Focus-And-DropDown $cmbMicDevice }
        else { $handled = $false }

        if ($handled) {
            $e.SuppressKeyPress = $true
            $e.Handled = $true
        }
    } catch {
        Write-Log "Tastenkürzel-Fehler: $($_.Exception.Message)"
    }
}

$form.Add_KeyDown({ param($sender, $e) Invoke-RecorderShortcut $e })
function Register-ShortcutHandlersRecursive {
    param([System.Windows.Forms.Control]$Root)
    try {
        foreach ($c in $Root.Controls) {
            try { $c.Add_KeyDown({ param($sender, $e) Invoke-RecorderShortcut $e }) } catch {}
            if ($c.Controls.Count -gt 0) { Register-ShortcutHandlersRecursive $c }
        }
    } catch { Write-Log "Shortcut-Registrierung fehlgeschlagen: $($_.Exception.Message)" }
}
Register-ShortcutHandlersRecursive $form

$form.Add_KeyUp({
    param($sender, $e)
    try {
        if ($e.Control -and $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Q) {
            Open-ConfiguredWebsite
            $e.SuppressKeyPress = $true
            $e.Handled = $true
        }
    } catch { Write-Log "Tastenkürzel-KeyUp-Fehler: $($_.Exception.Message)" }
})

$btnChooseFF.Add_Click({ [System.Windows.Forms.MessageBox]::Show('Die Aufnahme läuft jetzt nativ über C# / WASAPI. FFmpeg wird für die Aufnahme nicht benötigt.', 'Native Aufnahme', 'OK', 'Information') | Out-Null })
$btnDownloadFF.Add_Click({ [System.Windows.Forms.MessageBox]::Show('FFmpeg wird für die native WAV-Aufnahme nicht benötigt. MP3-Konvertierung kann später ergänzt werden.', 'FFmpeg nicht nötig', 'OK', 'Information') | Out-Null })
$btnDelete.Add_Click({ Delete-SelectedRecording })
$btnRename.Add_Click({ Rename-SelectedRecording })
$btnPlay.Add_Click({ Play-SelectedRecording })
$btnJump.Add_Click({ Jump-ToSelectedRecording })
$cmbFormat.Add_SelectedIndexChanged({ Update-FormatQualityState; Save-SettingsFromControls })
$cmbQuality.Add_SelectedIndexChanged({ Save-SettingsFromControls })
$cmbMicDevice.Add_SelectedIndexChanged({ Save-SettingsFromControls })
$chkMicSource.Add_CheckedChanged({ Save-SettingsFromControls })
$chkSystemSource.Add_CheckedChanged({ Save-SettingsFromControls })
$chkAutoSave.Add_CheckedChanged({ Save-SettingsFromControls })
$chkShowAfter.Add_CheckedChanged({ Save-SettingsFromControls })
$chkDebug.Add_CheckedChanged({ Save-SettingsFromControls })
$chkAlwaysOnTop.Add_CheckedChanged({ Save-SettingsFromControls })
$form.Add_Move({ Save-WindowPlacement })
$form.Add_ResizeEnd({ Save-WindowPlacement })

$form.Add_FormClosing({
    Save-WindowPlacement
    if ($script:IsRecording) {
        $answer = [System.Windows.Forms.MessageBox]::Show('Es läuft noch eine Aufnahme. Soll sie beendet und gespeichert werden?', 'Aufnahme läuft', 'YesNoCancel', 'Question')
        if ($answer -eq 'Cancel') { $_.Cancel = $true; return }
        if ($answer -eq 'Yes') { Stop-Recording }
        if ($answer -eq 'No') { try { if ($script:Recorder) { $script:Recorder.Dispose() } } catch {} }
    }
})

function Paint-LevelVisualizer {
    param(
        [System.Windows.Forms.Control]$Control,
        [System.Drawing.Graphics]$Graphics,
        [bool]$SourceActive
    )

    $Graphics.Clear([System.Drawing.Color]::Black)

    # Nicht gewählte Quelle bleibt leer.
    if (-not $SourceActive) { return }

    $w = [Math]::Max(1, $Control.Width)
    $hMax = [Math]::Max(1, $Control.Height - 2)

    # Vorbereitung / Leerlauf:
    # Nur eine ruhige grüne Grundlinie, keine künstlichen hohen Balken.
    if (-not $script:IsRecording -or $script:IsPaused) {
        $y = [Math]::Max(1, $Control.Height - 3)
        $Graphics.FillRectangle([System.Drawing.Brushes]::Lime, 0, $y, $w, 2)
        return
    }

    $rawLevel = 0.0
    try { $rawLevel = [double]$script:NativeLevel } catch { $rawLevel = 0.0 }
    if ($rawLevel -lt 0) { $rawLevel = 0.0 }
    if ($rawLevel -gt 1) { $rawLevel = 1.0 }

    # Sehr kleine Treiber-Schwankungen ignorieren.
    $noiseGate = 0.025

    # Wenn während der Aufnahme praktisch kein Signal anliegt: Grundlinie.
    if ($rawLevel -lt $noiseGate) {
        $y = [Math]::Max(1, $Control.Height - 3)
        $Graphics.FillRectangle([System.Drawing.Brushes]::Lime, 0, $y, $w, 2)
        return
    }

    # Aufnahme:
    # Equalizer-Optik wie Referenzbild: segmentierte Balken mit Grün/Gelb/Rot.
    $gap = 2
    $barWidth = 3
    $bars = [Math]::Max(14, [int](($w + $gap) / ($barWidth + $gap)))
    $totalW = ($bars * $barWidth) + (($bars - 1) * $gap)
    $startX = [int](($w - $totalW) / 2)
    if ($startX -lt 0) { $startX = 0 }

    $level = [Math]::Min(1.0, ($rawLevel - $noiseGate) / (1.0 - $noiseGate))
    $tick = (Get-Date).Millisecond / 100.0

    $segH = 2
    $segGap = 1
    $step = $segH + $segGap

    for ($i = 0; $i -lt $bars; $i++) {
        # Mischung aus Pegel und Spektrumform, damit es bei Aufnahme lebendig aussieht.
        $wave1 = [Math]::Abs([Math]::Sin(($i / 2.8) + $tick))
        $wave2 = [Math]::Abs([Math]::Sin(($i / 5.4) - ($tick * 0.7)))
        $shape = 0.28 + ($wave1 * 0.48) + ($wave2 * 0.24)
        if ($shape -gt 1) { $shape = 1 }

        $barH = [int](4 + ($level * $shape * ($hMax - 2)))
        if ($barH -gt $hMax) { $barH = $hMax }
        if ($barH -lt 2) { $barH = 2 }

        $x = $startX + ($i * ($barWidth + $gap))
        $segments = [Math]::Max(1, [int]($barH / $step))

        for ($s = 0; $s -lt $segments; $s++) {
            $segTop = $Control.Height - (($s + 1) * $step)
            if ($segTop -lt 1) { continue }

            $ratio = (($s + 1) * $step) / [double]$hMax
            if ($ratio -ge 0.78) {
                $brush = [System.Drawing.Brushes]::Red
            } elseif ($ratio -ge 0.58) {
                $brush = [System.Drawing.Brushes]::Orange
            } else {
                $brush = [System.Drawing.Brushes]::Lime
            }

            $Graphics.FillRectangle($brush, $x, $segTop, $barWidth, $segH)
        }
    }
}

$micVisualizer.Add_Paint({
    param($sender, $e)
    $active = ($script:Config.source -eq 'Mikrofon' -or $script:Config.source -eq 'System-Sound + Mikrofon')
    Paint-LevelVisualizer $sender $e.Graphics $active
})

$systemVisualizer.Add_Paint({
    param($sender, $e)
    $active = ($script:Config.source -eq 'System-Sound' -or $script:Config.source -eq 'System-Sound + Mikrofon')
    Paint-LevelVisualizer $sender $e.Graphics $active
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({ try { if ($script:IsRecording -and $script:Recorder) { $script:NativeLevel = [double]$script:Recorder.Level } } catch { $script:NativeLevel = 0.0 }; Update-StatusLine; $micVisualizer.Invalidate(); $systemVisualizer.Invalidate() })
$timer.Start()


$form.Add_Activated({
    try {
        if ($script:RestoreTopMostOnReturn -and [bool]$script:Config.alwaysOnTop) {
            $form.TopMost = $true
            $script:RestoreTopMostOnReturn = $false
            Write-Log 'Vordergrundmodus nach Rückkehr zum Recorder wieder aktiviert.'
        }

        # Wichtig: Wenn im SpeedCommander/Explorer Dateien gelöscht, umbenannt oder ergänzt wurden,
        # muss die interne Tabelle beim Zurückkommen sofort mit dem Ordner abgeglichen werden.
        Sync-AfterExternalReturn 'Form.Activated'
    } catch {
        Write-Log "Vordergrund-Rückkehr/Ordnerabgleich fehlgeschlagen: $($_.Exception.Message)"
    }
})

Sync-SettingsToControls
Refresh-Grid
Update-RecorderLayout
Set-RecordingUiState
Show-View 'Standard'
Write-Log "Programm gestartet. Version $script:AppVersion; Aktionsleisten-Icons kommen aus recorder-config.json."

$form.Add_FormClosing({ try { if ($script:IsPlaying) { Stop-Playback } } catch {} })
[void]$form.ShowDialog()
