# Setup notes

Things this repo does **not** capture. Redo these by hand after a rebuild.

## Monitors

| Device | Hardware ID | Resolution | Role |
|---|---|---|---|
| `\\.\DISPLAY2` | GWD0156 | 1080×1920 portrait | ARZOPA — no bar, no dock |
| `\\.\DISPLAY3` | DELA245 | 3840×2160 | AW3225QF, primary |
| `\\.\DISPLAY1` | AOC2703 | 2560×1440 | AOC |

Zebar's monitor indices are a **separate** numbering: index 0 is the ARZOPA,
so `zpack.json` presets target indices 1 and 2. Re-probe with
`./scripts/patch-bar-monitors.sh probe <n>` if displays change.

## Windhawk

Install: `winget install RamenSoftware.Windhawk`

1. **Taskbar auto-hide per monitor**
   - Windows Settings → Personalization → Taskbar → enable *Automatically hide the taskbar* (global).
   - Mod settings: add two items, exempting the monitors that should stay visible:
     - Monitor interface name `DELA245`, Auto-hide disabled = **on**
     - Monitor interface name `AOC2703`, Auto-hide disabled = **on**
   - No entry for `GWD0156` — its absence is what leaves it auto-hiding, which
     also releases the reserved work area so GlazeWM gets the full screen.

2. **Windows 11 Taskbar Styler**
   - Theme: **SimplyTransparent**

## Task Scheduler

Keeps the dock hidden on the portrait monitor across explorer restarts
(including every `rice` call).

- Trigger: At log on, delay 30 seconds
- Action: `powershell.exe`
- Arguments:
  `-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\zaina\.local\bin\Hide-TaskbarOnMonitor.ps1" -Watch`
- Uncheck *Stop the task if it runs longer than…*

## Wallpaper Engine

- Settings → General → **Monitor identification: Device path** (set before assigning wallpapers)
- Displays → **Wallpaper per Display**, then double-click each monitor to assign
- Settings → General → **Adjust Windows color: Accent color**
- Windows Settings → Personalization → Colors → Accent colour **not** Automatic (it fights WE)
- Performance → **Pause per monitor**

## Python / pywal

```
winget install Python.Python.3.13
py -3.13 -m pip install pywal16 haishoku colorthief
```

Disable the Microsoft Store aliases for `python.exe` / `python3.exe` under
Settings → Apps → Advanced app settings → App execution aliases, or the Store
stub shadows the real interpreter.

## First-run order

```
./scripts/patch-bar-monitors.sh set 1 2
./scripts/walsync.sh wire
chezmoi apply
rice aqua
./scripts/walsync.sh source "<path to a wallpaper preview.jpg>"
```

After that the `rice` shell function (defined in `.zshrc`) runs `walsync gen`
and `walsync glaze` automatically — both must come *after* rice.sh, which wipes
the deployed Zebar folder and rewrites `config.yaml`.
