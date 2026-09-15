<#
.SYNOPSIS
    Hides the Windows 11 taskbar on specific monitors only.

.DESCRIPTION
    Windows has no per-monitor taskbar visibility setting. This finds the
    taskbar windows (Shell_TrayWnd on the primary display,
    Shell_SecondaryTrayWnd on the others) and calls ShowWindow(SW_HIDE) on
    the ones sitting on the monitors you target.

    Default target is any monitor in portrait orientation (height > width).

.EXAMPLE
    .\Hide-TaskbarOnMonitor.ps1 -List
    Show every taskbar window found and which display it lives on.

.EXAMPLE
    .\Hide-TaskbarOnMonitor.ps1 -Watch
    Hide the portrait monitor's taskbar and keep it hidden across
    explorer.exe restarts. Leave running (or launch at logon).

.EXAMPLE
    .\Hide-TaskbarOnMonitor.ps1 -DeviceName '\\.\DISPLAY3'
    Target one specific display instead of using orientation.

.EXAMPLE
    .\Hide-TaskbarOnMonitor.ps1 -Show
    Undo — bring the hidden taskbars back.

.NOTES
    Hiding the window does NOT release the screen space Explorer reserved
    for the taskbar. Pair this with the Windhawk "Taskbar auto-hide per
    monitor" mod (set that monitor to auto-hide) so the work area is freed
    and tiling gets the full screen.
#>
[CmdletBinding()]
param(
    [string[]]$DeviceName,
    [switch]$Portrait,
    [switch]$List,
    [switch]$Show,
    [switch]$Watch,
    [int]$IntervalSeconds = 3,
    [int]$StartupDelaySeconds = 45
)

if (-not ('Win32.TaskbarHider' -as [type])) {
@'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace Win32 {
  public static class TaskbarHider {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW")]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFOEX {
      public int cbSize;
      public RECT rcMonitor;
      public RECT rcWork;
      public uint dwFlags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
      public string szDevice;
    }

    public class BarInfo {
      public IntPtr Handle;
      public string ClassName;
      public string Device;
      public int Width;
      public int Height;
      public bool IsPrimary;
      public bool IsVisible;
    }

    public static List<BarInfo> FindTaskbars() {
      List<BarInfo> found = new List<BarInfo>();
      EnumWindows(delegate(IntPtr h, IntPtr l) {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, sb.Capacity);
        string cls = sb.ToString();
        if (cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") {
          IntPtr hMon = MonitorFromWindow(h, 2u); // MONITOR_DEFAULTTONEAREST
          MONITORINFOEX mi = new MONITORINFOEX();
          mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
          if (GetMonitorInfo(hMon, ref mi)) {
            BarInfo bi = new BarInfo();
            bi.Handle    = h;
            bi.ClassName = cls;
            bi.Device    = mi.szDevice;
            bi.Width     = mi.rcMonitor.Right - mi.rcMonitor.Left;
            bi.Height    = mi.rcMonitor.Bottom - mi.rcMonitor.Top;
            bi.IsPrimary = (mi.dwFlags & 1u) == 1u;
            bi.IsVisible = IsWindowVisible(h);
            found.Add(bi);
          }
        }
        return true;
      }, IntPtr.Zero);
      return found;
    }

    public static void SetVisible(IntPtr h, bool visible) {
      ShowWindow(h, visible ? 5 : 0); // SW_SHOW : SW_HIDE
    }
  }
}
'@ | ForEach-Object { Add-Type -TypeDefinition $_ -Language CSharp }
}

function Get-TargetBars {
    $bars = [Win32.TaskbarHider]::FindTaskbars()

    # HARD GUARD: never hide the primary taskbar.
    #
    # The primary display's taskbar is a Shell_TrayWnd; the portrait monitor's
    # is always a Shell_SecondaryTrayWnd. During boot, display metrics can be
    # reported wrong for a few seconds — a 4K screen at 150% scaling has been
    # seen reporting as portrait — and hiding is sticky, so a single bad read
    # would take out the main taskbar until manually restored. Excluding the
    # primary makes that impossible without losing anything we want to hide.
    $bars = $bars | Where-Object { -not $_.IsPrimary -and $_.ClassName -ne 'Shell_TrayWnd' }

    if ($DeviceName) {
        return $bars | Where-Object { $DeviceName -contains $_.Device }
    }

    # Default: portrait monitors. Require a clearly portrait aspect ratio
    # rather than just height > width, so a transient square-ish reading
    # during boot doesn't count.
    return $bars | Where-Object { $_.Height -gt ($_.Width * 1.2) }
}

if ($List) {
    [Win32.TaskbarHider]::FindTaskbars() | ForEach-Object {
        [pscustomobject]@{
            Handle      = ('0x{0:X}' -f [int64]$_.Handle)
            Class       = $_.ClassName
            Display     = $_.Device
            Resolution  = "$($_.Width)x$($_.Height)"
            Orientation = $(if ($_.Height -gt $_.Width) { 'portrait' } else { 'landscape' })
            Primary     = $_.IsPrimary
            Visible     = $_.IsVisible
        }
    } | Format-Table -AutoSize
    return
}

$makeVisible = [bool]$Show

function Invoke-Apply {
    # -Show must be able to restore ANY taskbar, including the primary one —
    # otherwise the guard in Get-TargetBars would block the very recovery this
    # script needs to perform. Hiding stays guarded.
    $bars = if ($makeVisible -and $DeviceName) {
        [Win32.TaskbarHider]::FindTaskbars() | Where-Object { $DeviceName -contains $_.Device }
    } elseif ($makeVisible) {
        [Win32.TaskbarHider]::FindTaskbars()
    } else {
        Get-TargetBars
    }

    foreach ($bar in $bars) {
        if ($bar.IsVisible -ne $makeVisible) {
            [Win32.TaskbarHider]::SetVisible($bar.Handle, $makeVisible)
            $verb = if ($makeVisible) { 'Shown' } else { 'Hidden' }
            Write-Verbose "$verb $($bar.ClassName) on $($bar.Device) ($($bar.Width)x$($bar.Height))"
        }
    }
}

if ($Watch) {
    # Displays can report wrong metrics for a while after logon. Wait before
    # the first pass so the watcher never acts on a half-initialised desktop.
    if ($StartupDelaySeconds -gt 0) {
        Write-Verbose "Waiting $StartupDelaySeconds s before first pass..."
        Start-Sleep -Seconds $StartupDelaySeconds
    }
    Write-Host "Watching. Ctrl+C to stop." -ForegroundColor Cyan
    while ($true) {
        Invoke-Apply
        Start-Sleep -Seconds $IntervalSeconds
    }
} else {
    Invoke-Apply
}
