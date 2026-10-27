# Records a short clip of the Excel window for the README: a countdown, then -Seconds of the window as it is on screen,
# made into Screenshots\<Name>.gif (shown inline on GitHub) and kept as Screenshots\<Name>.mp4.
# Needs ffmpeg on PATH. Excel's window stays where it is: move or resize it before recording (1280x800 reads well).
#   .\Record-Clip.ps1 -Name Trace
param(
    [Parameter(Mandatory)] [string] $Name,
    [double] $Seconds = 4,
    [int] $Countdown = 3,
    [int] $Width = 960,   # the GIF's width; its height follows the window's
    [int] $Fps = 12
)
$ErrorActionPreference = 'Stop'

$excel = Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object MainWindowTitle | Select-Object -First 1
if (-not $excel) { throw 'Open Excel (with the workbook to show) first.' }
$title = $excel.MainWindowTitle

# The window's place on screen in physical pixels. The desktop is recorded there, not the window itself: a window's own
# picture misses what Excel draws on the GPU and the tinykit windows over it (Chart Editor, overlays).
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class ClipWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT rect, int size);
}
"@
[ClipWin]::SetProcessDPIAware() | Out-Null
$rect = New-Object ClipWin+RECT
[ClipWin]::DwmGetWindowAttribute($excel.MainWindowHandle, 9, [ref]$rect, 16) | Out-Null   # DWMWA_EXTENDED_FRAME_BOUNDS
$size = '{0}x{1}' -f ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)

$folder = $PSScriptRoot
$mp4 = Join-Path $folder "$Name.mp4"
$gif = Join-Path $folder "$Name.gif"
$palette = Join-Path $env:TEMP "tinykit-clip-palette.png"

for ($i = $Countdown; $i -gt 0; $i--) {
    Write-Host "Recording '$title' in $i..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host "Recording $Seconds s - go." -ForegroundColor Green

# The window's part of the desktop, the cursor drawn; 30 fps while recording, cut down for the GIF.
ffmpeg -hide_banner -loglevel error -y -f gdigrab -framerate 30 -draw_mouse 1 -offset_x $rect.Left -offset_y $rect.Top `
    -video_size $size -t $Seconds -i desktop `
    -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 $mp4
if ($LASTEXITCODE -ne 0) { throw "ffmpeg could not record '$title'." }
Write-Host "Recorded $mp4"

# A palette of the clip's own colors: Excel's grid and text stay sharp in 256 colors.
$scale = "fps=$Fps,scale=${Width}:-1:flags=lanczos"
ffmpeg -hide_banner -loglevel error -y -i $mp4 -vf "$scale,palettegen=stats_mode=diff" $palette
ffmpeg -hide_banner -loglevel error -y -i $mp4 -i $palette -lavfi "$scale [x]; [x][1:v] paletteuse=dither=none:diff_mode=rectangle" -loop 0 $gif
Remove-Item $palette -ErrorAction SilentlyContinue
Write-Host ("Made {0} ({1:N0} KB)" -f $gif, ((Get-Item $gif).Length / 1KB)) -ForegroundColor Green
