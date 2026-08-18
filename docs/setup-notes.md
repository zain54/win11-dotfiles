# Setup notes

Things this repo does **not** capture. Redo these by hand after a rebuild.

GlazeWM was removed in August 2026 — too many app-compatibility problems
(games, launchers, overlays, MMC dialogs) for what tiling was worth. Zebar
stayed. If you ever reinstall GlazeWM, note that winget ships **both products
under the same package id** (`glzr-io.glazewm`), so `--all-versions` uninstalls
Zebar too.

## Monitors

| Device | Hardware ID | Resolution | Role |
|---|---|---|---|
| `\\.\DISPLAY2` | GWD0156 | 1080×1920 portrait | ARZOPA — no bar, no dock |
| `\\.\DISPLAY3` | DELA245 | 3840×2160 | AW3225QF, primary |
| `\\.\DISPLAY1` | AOC2703 | 2560×1440 | AOC |

Three unrelated numbering schemes are in play — don't assume they line up:

- **Zebar preset indices**: index 0 is the ARZOPA, so `zpack.json` targets 1 and 2.
  Re-probe with `./scripts/patch-bar-monitors.sh probe <n>` if displays change.
- **Wallpaper Engine keys**: `Monitor0` is the AW3225QF (see below).
- **Windows Settings display numbers**: whatever *Identify* shows.

## Windhawk

Install: `winget install RamenSoftware.Windhawk`

1. **Taskbar auto-hide per monitor**
   - Windows Settings → Personalization → Taskbar → enable *Automatically hide the taskbar* (global).
   - Mod settings: add two items, exempting the monitors that should stay visible:
     - Monitor interface name `DELA245`, Auto-hide disabled = **on**
     - Monitor interface name `AOC2703`, Auto-hide disabled = **on**
   - No entry for `GWD0156` — its absence is what leaves it auto-hiding.

2. **Windows 11 Taskbar Styler**
   - Theme: **SimplyTransparent**

## Background processes

All three start hidden via `~/.local/bin/start-watchers.vbs`. VBScript's
`WshShell.Run(..., 0, False)` is the only reliable way to get no console —
PowerShell's `-WindowStyle Hidden` and `mintty -w hide` both still show a
window when launched from Task Scheduler.

The script starts:

1. **Zebar** — the status bar. GlazeWM used to launch this via its
   `startup_commands`; the .vbs took that over. Binary lives at
   `C:\Program Files\glzr.io\Zebar\zebar.exe`.
2. `Hide-TaskbarOnMonitor.ps1 -Watch` — re-hides the dock on the portrait
   monitor after anything recreates it.
3. `walsync.sh watch` — repaints the palette when the WE wallpaper changes.

**One** scheduled task:

- Program: `wscript.exe`
- Arguments: `"C:\Users\zaina\.local\bin\start-watchers.vbs"`
- Trigger: At log on, delay 60 seconds
- Run only when user is logged on
- Uncheck *Stop the task if it runs longer than…*

If `bash.exe` isn't at `C:\msys64\usr\bin\bash.exe`, fix `bashExe` in the .vbs.

Don't launch Zebar from a terminal with `&` — it dies with the shell. Use the
.vbs, which detaches it properly.

## Wallpaper Engine

- Settings → General → **Monitor identification: Device path** (set before assigning wallpapers)
- Displays → **Wallpaper per Display**, then double-click each monitor to assign
- Settings → General → **Adjust Windows color: Accent color**
- Windows Settings → Personalization → Colors → Accent colour **not** Automatic (it fights WE)
- Performance → fullscreen pause rules now work properly, since windows are no
  longer tiled. Worth revisiting these.

The live wallpaper assignment lives at `wallpaperconfig.selectedwallpapers.Monitor0.file`
in `steamapps/common/wallpaper_engine/config.json`. Keys are generic
`Monitor0`/`Monitor1` — *not* device paths, despite the identification setting.
Saved profiles contain a second `selectedwallpapers` map nested under `config`,
so any lookup must anchor on the `wallpaperconfig` key specifically.

## Colour pipeline

The **wallpaper** owns colour; the **theme** owns fonts, icons and layout.
`walsync sync` regenerates the palette and pushes it to:

- **Zebar** — `wal.css` of `--color-*` overrides, linked from each theme's
  `bar.html` (see `walsync wire`)
- **Windows Terminal** — a `wal` scheme in `settings.json`, set as
  `profiles.defaults.colorScheme`. Requires settings.json to be comment-free
  JSON; if jq refuses it, open Terminal's settings UI and save once.
- **VS Code** — via the `dlasagno.wal-theme` marketplace extension, which reads
  `~/.cache/wal/colors.json` and self-updates. Install it manually. Last
  released five years ago, so unmaintained; if a VS Code update breaks it,
  there's no fix coming.

`rice.sh`'s colour-setting lines were stripped to avoid fighting this:
the Windows Terminal `colorScheme` jq line is gone (the font line stays), and
`workbench.colorTheme` / `workbench.colorCustomizations` were deleted from every
theme's `vscode-theme-settings.json`. `set_glazewm_config` is no longer called.

`walsync unwire` reverts to theme-owned bar colours if you change your mind.

## Python / pywal

```
winget install Python.Python.3.13
py -3.13 -m pip install pywal16 haishoku colorthief colorz
```

Disable the Microsoft Store aliases for `python.exe` / `python3.exe` under
Settings → Apps → Advanced app settings → App execution aliases, or the Store
stub shadows the real interpreter.

## Windows Terminal

`launchMode` must be `"default"`. The upstream dotfiles set it to `"focus"`,
which hides the title bar — fine under a tiling WM, useless without one (no
close button, no dragging). `Ctrl`+`Shift`+`F11` toggles focus mode per-window
if you want it occasionally.

`` Win+` `` opens Quake mode, which replaces the old `alt`+`enter` GlazeWM
binding for a quick terminal.

## Workspaces

Native Windows virtual desktops replaced GlazeWM's. `Win`+`Ctrl`+`D` creates,
`Win`+`Ctrl`+`←`/`→` switches, `Win`+`Tab` shows the overview.

Two things GlazeWM did that these don't: jump directly to desktop N, and switch
one monitor independently of the others. If either becomes annoying, the path
is MScholtes' `VirtualDesktop.exe` (which supports jump-to-N) driven either from
AutoHotkey or a Zebar widget via the `shell` provider — Zebar has no
virtual-desktop provider, so the indicator would need to poll.

## First-run order

```
./scripts/patch-bar-monitors.sh set 1 2
./scripts/walsync.sh wire
chezmoi apply
rice aqua
./scripts/walsync.sh we-current     # confirm auto-detection resolves
```

After that the `rice` zsh function runs `walsync sync` automatically — and
`sync` must come *after* rice.sh, which wipes the deployed Zebar folder.

## Gotchas worth remembering

- **`wire` can report "Wired 0 file(s)" while themes are still unwired.**
  Verify with `grep -l 'wal.css' .dotfile/dot_rice-manager/rices/*/dotfile-bar/bar.html`
  and re-run until all five appear. The same one-theme-at-a-time failure hit
  `strip-glazewm-bar.sh`; check its work the same way.
- **Ten theme folders have `vscode-theme-settings.json`, only five have a
  `dotfile-bar`.** The other five are older themes using the legacy
  `zebar-config.yaml` format, so bar scripts touch five and VS Code scripts
  touch ten. That asymmetry is correct.
- **Near-monochrome wallpapers crash pywal's haishoku backend.** walsync falls
  through to colorthief, wal, then colorz, and keeps the old palette if all fail.
- **Video wallpapers ship `preview.gif`.** pywal samples only the first frame,
  so palettes can come out darker than the wallpaper looks.
- **`chezmoi apply` prompts about files that other tools rewrite at runtime**
  (`.glzr/zebar/dotfile-bar/*`, Windows Terminal's settings.json). Skip those.
  Answer overwrite only when the chezmoi source holds a change you actually want
  deployed.
