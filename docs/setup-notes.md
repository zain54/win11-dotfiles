# Setup notes

Things this repo does **not** capture. Redo these by hand after a rebuild.

## Monitors

| Device | Hardware ID | Resolution | Role |
|---|---|---|---|
| `\\.\DISPLAY2` | GWD0156 | 1080×1920 portrait | ARZOPA — no bar, no dock |
| `\\.\DISPLAY3` | DELA245 | 3840×2160 | AW3225QF, primary |
| `\\.\DISPLAY1` | AOC2703 | 2560×1440 | AOC |

Four unrelated numbering schemes are in play — don't assume they line up:

- **GlazeWM `bind_to_monitor`**: 0 = portrait, 1 = main, 2 = AOC.
- **Zebar preset indices**: index 0 is the ARZOPA, so `zpack.json` targets 1 and 2.
  Re-probe with `./scripts/patch-bar-monitors.sh probe <n>` if displays change.
- **Wallpaper Engine keys**: `Monitor0` is the AW3225QF (see below).
- **Windows Settings display numbers**: whatever *Identify* shows.

## Workspaces

Workspaces 1–7 bind to the main AW3225QF; 8, 9 and 0 bind to the AOC.
`LeftMonitorFix` is a `keep_alive: false` placeholder the portrait monitor
needs — don't remove it. There used to be a matching `RightMonitorFix`; it was
deleted, because a second workspace bound to monitor 2 competed with 8/9/0 for
display and the AOC kept showing the placeholder instead.

Two rules follow the workspaces to the AOC by design: Streamlabs opens on 9,
and Taskmgr/vsthost/Mechvibes on 0.

**`bind_to_monitor` only applies when a workspace is created.** Changing it and
running `wm-reload-config` (`alt`+`shift`+`r`) does nothing to workspaces that
already exist — GlazeWM has to fully exit (`alt`+`shift`+`e`) and relaunch.
Exiting kills Zebar via `shutdown_commands`, so run `./scripts/walsync.sh sync`
afterwards to restore the palette.

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

## Background watchers

Both run hidden via `~/.local/bin/start-watchers.vbs`. VBScript's
`WshShell.Run(..., 0, False)` is the only reliable way to get no console —
PowerShell's `-WindowStyle Hidden` and `mintty -w hide` both still show a
window when launched from Task Scheduler.

The script starts:

1. `Hide-TaskbarOnMonitor.ps1 -Watch` — re-hides the dock on the portrait
   monitor after anything recreates it (including every `rice` call).
2. `walsync.sh watch` — repaints the palette when the WE wallpaper changes.

**One** scheduled task, not two:

- Program: `wscript.exe`
- Arguments: `"C:\Users\zaina\.local\bin\start-watchers.vbs"`
- Trigger: At log on, delay 60 seconds
- Run only when user is logged on
- Uncheck *Stop the task if it runs longer than…*

If `bash.exe` isn't at `C:\msys64\usr\bin\bash.exe`, fix `bashExe` in the .vbs.

## Wallpaper Engine

- Settings → General → **Monitor identification: Device path** (set before assigning wallpapers)
- Displays → **Wallpaper per Display**, then double-click each monitor to assign
- Settings → General → **Adjust Windows color: Accent color**
- Windows Settings → Personalization → Colors → Accent colour **not** Automatic (it fights WE)
- Performance → **Pause per monitor**

The live wallpaper assignment lives at `wallpaperconfig.selectedwallpapers.Monitor0.file`
in `steamapps/common/wallpaper_engine/config.json`. Keys are generic
`Monitor0`/`Monitor1` — *not* device paths, despite the identification setting.
Saved profiles contain a second `selectedwallpapers` map nested under `config`,
so any lookup must anchor on the `wallpaperconfig` key specifically.

## Python / pywal

```
winget install Python.Python.3.13
py -3.13 -m pip install pywal16 haishoku colorthief colorz
```

Disable the Microsoft Store aliases for `python.exe` / `python3.exe` under
Settings → Apps → Advanced app settings → App execution aliases, or the Store
stub shadows the real interpreter.

## GlazeWM ignore rules

Apps that break when tiled go in the first `window_rules` block
(`commands: ["ignore"]`). Currently: the League client, `mmc` (Task Scheduler,
Event Viewer, Services — their dialogs get cut off and you can't reach the
buttons), HoYoPlay and its games
(`HYP|GenshinImpact|YuanShen|StarRail|BH3|ZenlessZoneZero`), and upstream's
list of six specific game executables.

That upstream games regex is *not* a general rule — it's jade-tam's personal
list, so anything you play that isn't in it gets tiled. There is no canonical
community ignore list; everyone maintains their own.

`alt`+`shift`+`i` is bound to `ignore` as a general escape hatch — hit it when
something misbehaves rather than editing YAML mid-session. Note ignoring is
one-way; the only way back is `alt`+`shift`+`r`.

`alt`+`shift`+`space` floats the focused window as a one-off.

`state_defaults.fullscreen.shown_on_top` is set to `false` (upstream's default,
though this repo shipped `true`). Forcing fullscreen windows always-on-top
pushes overlays like Blitz and Discord underneath them.

To find a process name: `glazewm query windows | jq -r '.data.windows[] | "\(.processName)  |  \(.title)"'`

Note `config.yaml` is rewritten by both `rice.sh` and `walsync glaze`, so edit
it via `chezmoi edit ~/.glzr/glazewm/config.yaml`, then `chezmoi apply`, then
`./scripts/walsync.sh glaze` to restore the palette borders.

## First-run order

```
./scripts/patch-bar-monitors.sh set 1 2
./scripts/walsync.sh wire
chezmoi apply
rice aqua
./scripts/walsync.sh we-current     # confirm auto-detection resolves
```

After that the `rice` zsh function runs `walsync sync` automatically — and
`sync` must come *after* rice.sh, which wipes the deployed Zebar folder and
rewrites `config.yaml`.

## Gotchas worth remembering

- **`wire` can report "Wired 0 file(s)" while themes are still unwired.**
  Verify with `grep -l 'wal.css' .dotfile/dot_rice-manager/rices/*/dotfile-bar/bar.html`
  and re-run until all five appear.
- **The wallpaper owns bar colours, not the theme.** All five themes therefore
  look similar in colour and differ mainly in fonts and layout. `walsync unwire`
  reverts to theme-owned colours.
- **Near-monochrome wallpapers crash pywal's haishoku backend.** walsync falls
  through to colorthief, wal, then colorz, and keeps the old palette if all fail.
- **Video wallpapers ship `preview.gif`.** pywal samples only the first frame,
  so palettes can come out darker than the wallpaper looks.
