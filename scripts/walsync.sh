#!/usr/bin/env bash
#
# walsync.sh — derive a colour palette from the current Wallpaper Engine
# wallpaper and push it into Windows Terminal (and, via the Wal Theme
# extension reading ~/.cache/wal/colors.json, into VS Code).
#
# Usage:
#   ./walsync.sh source <image>         # remember which image drives the palette
#   ./walsync.sh gen [image]            # build the palette (uses saved source if omitted)
#   ./walsync.sh gen <image> -b wal     # pick a different pywal backend
#   ./walsync.sh sync [image]           # gen + term (use after a wallpaper change)
#   ./walsync.sh term                   # push palette into Windows Terminal
#   ./walsync.sh show                   # print the current palette
#   ./walsync.sh we-current [key]       # show the wallpaper currently on that monitor
#   ./walsync.sh watch [seconds]        # resync automatically when WE's wallpaper changes
#   ./walsync.sh we-scan                # list Wallpaper Engine wallpapers + previews
#
# Backends worth trying: haishoku (default here), colorthief, wal, colorz.
#
# Requires: python + pywal16  (pip install pywal16 haishoku colorthief)

set -euo pipefail

BACKEND="haishoku"
CACHE="$HOME/.cache/wal/colors.json"
SOURCE_FILE="$HOME/.config/walsync/source"

have() { command -v "$1" >/dev/null 2>&1; }

wal_cmd() {
  # pywal16 installs as `wal`; on Windows it may only exist as a python module.
  if have wal; then wal "$@"
  else python -m pywal "$@"
  fi
}

set_source() {
  mkdir -p "$(dirname "$SOURCE_FILE")"
  printf '%s\n' "$1" > "$SOURCE_FILE"
  echo "Palette source set to: $1"
}

gen() {
  local img="${1:-}"
  if [ -z "$img" ]; then
    if img="$(we_current 2>/dev/null)" && [ -n "$img" ]; then
      echo "Auto-detected wallpaper for $WE_MONITOR_KEY: $img"
    elif [ -f "$SOURCE_FILE" ]; then
      img="$(cat "$SOURCE_FILE")"
      echo "Auto-detect failed; using saved source: $img"
    else
      echo "No image given, auto-detect failed, and no saved source."
      echo "Run: $0 we-current   to debug, or: $0 gen <image>"
      exit 1
    fi
  fi
  [ -f "$img" ] || { echo "No such image: $img"; exit 1; }
  set_source "$img" >/dev/null

  local winimg b tried ok
  winimg="$(cygpath -w "$img" 2>/dev/null || printf '%s' "$img")"
  ok=0
  tried=""

  # Some images (near-monochrome ones especially) make a backend return fewer
  # than 16 colours, which pywal then crashes on. Fall through to another.
  for b in "$BACKEND" colorthief wal colorz; do
    case " $tried " in *" $b "*) continue ;; esac
    tried="$tried $b"
    if wal_cmd -i "$winimg" --backend "$b" -n -s -t -e 2>/dev/null; then
      BACKEND="$b"; ok=1; break
    fi
    echo "  backend '$b' failed, trying next..."
  done

  if [ "$ok" -eq 0 ]; then
    echo "All backends failed on: $img" >&2
    echo "Keeping the existing palette." >&2
    return 1
  fi

  [ -f "$CACHE" ] || { echo "pywal did not write $CACHE"; exit 1; }
  echo "Palette written to $CACHE (backend: $BACKEND)"
  show
}

show() {
  [ -f "$CACHE" ] || { echo "No palette yet — run: $0 gen <image>"; exit 1; }
  echo
  jq -r '.colors | to_entries[] | "\(.key)\t\(.value)"' "$CACHE" |
    while IFS=$'\t' read -r name hex; do
      local r g b
      r=$((16#${hex:1:2})); g=$((16#${hex:3:2})); b=$((16#${hex:5:2}))
      printf '\033[48;2;%d;%d;%dm    \033[0m %-8s %s\n' "$r" "$g" "$b" "$name" "$hex"
    done
}

palette_color() {  # palette_color <key>  — colorN, or background/foreground
  case "$1" in
    background|foreground|cursor) jq -r ".special.$1" "$CACHE" ;;
    *)                            jq -r ".colors.$1"  "$CACHE" ;;
  esac
}

we_config() {
  local c
  for c in \
    "/c/Program Files (x86)/Steam/steamapps/common/wallpaper_engine/config.json" \
    "/d/SteamLibrary/steamapps/common/wallpaper_engine/config.json" \
    "/e/SteamLibrary/steamapps/common/wallpaper_engine/config.json"
  do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Path of the wallpaper asset currently assigned to $WE_MONITOR_KEY.
we_wallpaper_file() {
  local cfg
  cfg="$(we_config)" || { echo "Can't find Wallpaper Engine config.json" >&2; return 1; }

  # Target the live `wallpaperconfig` block. Saved profiles also contain a
  # `selectedwallpapers` map, but nested under `config`, so anchor on the key.
  jq -r --arg mon "$WE_MONITOR_KEY" '
    [paths as $p | select($p[-1] == "wallpaperconfig") | $p] as $wp
    | if ($wp | length) == 0 then empty
      else getpath($wp[0]).selectedwallpapers[$mon].file // empty
      end
  ' "$cfg" 2>/dev/null | head -n1
}

# Preview image for that wallpaper (pywal can't sample a running scene).
we_current() {
  local file dir preview
  file="$(we_wallpaper_file)"
  [ -n "$file" ] || {
    echo "No wallpaper found for $WE_MONITOR_KEY" >&2
    echo "Available monitor keys:" >&2
    jq -r '[paths as $p | select($p[-1] == "wallpaperconfig") | $p] as $wp
           | getpath($wp[0]).selectedwallpapers | keys[]' "$(we_config)" >&2 2>/dev/null
    return 1
  }
  dir="$(dirname "$(cygpath -u "$file" 2>/dev/null || printf '%s' "$file")")"
  preview="$(ls "$dir"/preview.* 2>/dev/null | head -n1 || true)"
  [ -n "$preview" ] || { echo "No preview.* in $dir" >&2; return 1; }
  printf '%s\n' "$preview"
}

# Poll config.json; resync when the primary monitor's wallpaper actually changes.
watch_we() {
  local cfg interval last_mtime mtime current saved
  cfg="$(we_config)" || { echo "Can't find Wallpaper Engine config.json" >&2; exit 1; }
  interval="${1:-5}"
  last_mtime=""
  echo "Watching $cfg every ${interval}s. Ctrl+C to stop."

  while true; do
    mtime="$(stat -c %Y "$cfg" 2>/dev/null || echo 0)"
    if [ "$mtime" != "$last_mtime" ]; then
      last_mtime="$mtime"
      current="$(we_current 2>/dev/null || true)"
      saved="$([ -f "$SOURCE_FILE" ] && cat "$SOURCE_FILE" || true)"
      if [ -n "$current" ] && [ "$current" != "$saved" ]; then
        echo "Wallpaper changed -> $current"
        sync_all "$current" || echo "  sync failed; continuing to watch."
      fi
    fi
    sleep "$interval"
  done
}

WT_SETTINGS="$HOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
WT_SCHEME_NAME="wal"

# Push the palette into Windows Terminal as a colour scheme, and make it the
# default for every profile.
term() {
  [ -f "$CACHE" ]       || { echo "No palette yet — run: $0 gen <image>"; exit 1; }
  [ -f "$WT_SETTINGS" ] || { echo "No Windows Terminal settings at $WT_SETTINGS" >&2; return 1; }

  # settings.json is JSONC when Terminal has written its default comments.
  if ! jq empty "$WT_SETTINGS" 2>/dev/null; then
    echo "Windows Terminal settings.json isn't valid JSON (comments?)." >&2
    echo "Open Terminal's settings UI and save once to normalise it, then retry." >&2
    return 1
  fi

  local scheme tmp
  scheme="$(jq --arg name "$WT_SCHEME_NAME" '
    .colors as $c | .special as $s | {
      name:                  $name,
      background:            $s.background,
      foreground:            $s.foreground,
      cursorColor:           $s.cursor,
      selectionBackground:   $c.color8,
      black:                 $c.color0,
      red:                   $c.color1,
      green:                 $c.color2,
      yellow:                $c.color3,
      blue:                  $c.color4,
      purple:                $c.color5,
      cyan:                  $c.color6,
      white:                 $c.color7,
      brightBlack:           $c.color8,
      brightRed:             $c.color9,
      brightGreen:           $c.color10,
      brightYellow:          $c.color11,
      brightBlue:            $c.color12,
      brightPurple:          $c.color13,
      brightCyan:            $c.color14,
      brightWhite:           $c.color15
    }' "$CACHE")"

  tmp="$(mktemp)"
  jq --argjson scheme "$scheme" --arg name "$WT_SCHEME_NAME" '
    .schemes = (((.schemes // []) | map(select(.name != $name))) + [$scheme])
    | .profiles.defaults.colorScheme = $name
  ' "$WT_SETTINGS" > "$tmp"
  mv "$tmp" "$WT_SETTINGS"
  echo "Windows Terminal scheme '$WT_SCHEME_NAME' updated."
}

sync_all() {  # sync_all [image]
  gen "${1:-}" || return 1
  term || true
}

we_scan() {
  local roots=(
    "/c/Program Files (x86)/Steam/steamapps/workshop/content/431960"
    "/d/SteamLibrary/steamapps/workshop/content/431960"
    "/e/SteamLibrary/steamapps/workshop/content/431960"
  )
  local found=0
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    found=1
    echo "== $root"
    for d in "$root"/*/; do
      local id title preview
      id="$(basename "$d")"
      title="$(jq -r '.title // "?"' "$d/project.json" 2>/dev/null || echo '?')"
      preview="$(ls "$d"preview.* 2>/dev/null | head -n1 || true)"
      printf '  %-12s %-40s %s\n' "$id" "${title:0:40}" "${preview:-no preview}"
    done
  done
  [ "$found" -eq 1 ] || echo "No workshop folder found — pass your Steam library path manually."
}

cmd="${1:-}"; shift || true
case "$cmd" in
  gen)
    img=""
    if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then img="$1"; shift; fi
    while [ $# -gt 0 ]; do
      case "$1" in
        -b|--backend) BACKEND="$2"; shift 2 ;;
        *) echo "unknown option: $1"; exit 1 ;;
      esac
    done
    gen "$img"
    ;;
  source)
    [ $# -eq 1 ] || { echo "source needs one image path"; exit 1; }
    [ -f "$1" ] || { echo "No such image: $1"; exit 1; }
    set_source "$1"
    ;;
  sync)
    img=""
    if [ $# -ge 1 ]; then img="$1"; shift; fi
    sync_all "$img"
    ;;
  show)    show ;;
  term)    term ;;
  we-current)
    [ $# -eq 0 ] || WE_MONITOR_KEY="$1"
    we_current
    ;;
  watch)
    watch_we "${1:-5}"
    ;;
  we-scan) we_scan ;;
  *) sed -n '3,16p' "$0"; exit 1 ;;
esac
