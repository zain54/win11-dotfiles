#!/usr/bin/env bash
#
# patch-bar-monitors.sh — set Zebar's monitorSelection across every theme.
#
# Edits the chezmoi SOURCE tree so the change survives both `chezmoi apply`
# and `rice <theme>` (which rm -rf's ~/.glzr/zebar/dotfile-bar and re-copies
# from the theme folder).
#
# Usage:
#   ./patch-bar-monitors.sh probe 0        # one bar, monitor index 0 only
#   ./patch-bar-monitors.sh set 0 2        # bars on indices 0 and 2
#   ./patch-bar-monitors.sh name "\\\\.\\DISPLAY3" "\\\\.\\DISPLAY1"
#   ./patch-bar-monitors.sh reset          # back to a single "all" preset
#   ./patch-bar-monitors.sh show           # print current selections
#
# Requires: jq  (pacman -S jq)

set -euo pipefail

command -v jq >/dev/null || { echo "jq not found — pacman -S jq"; exit 1; }

PACK="dotfile-bar"

# chezmoi is a Windows binary and emits Windows paths.
to_unix() { cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }

SRC="$(to_unix "$(chezmoi source-path)")"
RICES="$SRC/dot_rice-manager/rices"
[ -d "$RICES" ] || { echo "Can't find $RICES"; exit 1; }

mapfile -t ZPACKS < <(find "$RICES" -path "*/$PACK/zpack.json" | sort)
[ "${#ZPACKS[@]}" -gt 0 ] || { echo "No $PACK/zpack.json under $RICES"; exit 1; }

# settings.json lives outside the theme folders; it may or may not be managed.
if SETTINGS_SRC="$(chezmoi source-path "$(cygpath -w "$HOME/.glzr/zebar/settings.json")" 2>/dev/null)"; then
  SETTINGS="$(to_unix "$SETTINGS_SRC")"
  SETTINGS_NOTE="(chezmoi source)"
else
  SETTINGS="$HOME/.glzr/zebar/settings.json"
  SETTINGS_NOTE="(unmanaged, editing live file)"
fi

write_json() {  # write_json <file> <jq-filter> [jq args...]
  local file="$1"; shift
  local filter="$1"; shift
  local tmp; tmp="$(mktemp)"
  jq "$@" "$filter" "$file" > "$tmp"
  mv "$tmp" "$file"
}

apply_specs() {  # apply_specs <specs-json>
  local specs="$1"
  local widget=""

  for zp in "${ZPACKS[@]}"; do
    write_json "$zp" '
      .widgets |= map(
        if (.presets? | type) == "array" and (.presets | length) > 0 then
          (.presets[0]) as $tpl
          | .presets = [ $specs[] | $tpl + { name: .name, monitorSelection: .sel } ]
        else . end
      )
    ' --argjson specs "$specs"
    echo "  patched ${zp#$RICES/}"
    [ -n "$widget" ] || widget="$(jq -r '.widgets[0].name' "$zp")"
  done

  # Rebuild startupConfigs for this pack, leaving any other pack's entries alone.
  write_json "$SETTINGS" '
    .startupConfigs = (
      ((.startupConfigs // []) | map(select(.pack != $pack)))
      + [ $specs[] | { pack: $pack, widget: $widget, preset: .name } ]
    )
  ' --arg pack "$PACK" --arg widget "$widget" --argjson specs "$specs"
  echo "  patched settings.json $SETTINGS_NOTE"
}

specs_from_indices() {
  local out="[]"
  for i in "$@"; do
    out="$(jq -c --argjson i "$i" '. + [{name: ("mon" + ($i|tostring)),
                                         sel: {type: "index", match: $i}}]' <<<"$out")"
  done
  printf '%s' "$out"
}

specs_from_names() {
  local out="[]" n=0
  for m in "$@"; do
    out="$(jq -c --arg m "$m" --argjson n "$n" \
      '. + [{name: ("mon" + ($n|tostring)), sel: {type: "name", match: $m}}]' <<<"$out")"
    n=$((n+1))
  done
  printf '%s' "$out"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  probe)
    [ $# -eq 1 ] || { echo "probe takes exactly one index"; exit 1; }
    echo "Probing monitor index $1 — expect ONE bar."
    apply_specs "$(jq -cn --argjson i "$1" \
      '[{name: "probe", sel: {type: "index", match: $i}}]')"
    ;;
  set)
    [ $# -ge 1 ] || { echo "set needs at least one index"; exit 1; }
    echo "Setting bars on monitor indices: $*"
    apply_specs "$(specs_from_indices "$@")"
    ;;
  name)
    [ $# -ge 1 ] || { echo "name needs at least one monitor name"; exit 1; }
    echo "Setting bars on monitors: $*"
    apply_specs "$(specs_from_names "$@")"
    ;;
  reset)
    echo "Restoring single all-monitors preset."
    apply_specs '[{"name": "default", "sel": {"type": "all"}}]'
    ;;
  show)
    for zp in "${ZPACKS[@]}"; do
      echo "${zp#$RICES/}:"
      jq -r '.widgets[].presets[] | "  \(.name)  \(.monitorSelection|tostring)"' "$zp"
    done
    echo "settings.json $SETTINGS_NOTE:"
    jq -r '.startupConfigs[] | "  \(.pack)/\(.widget)/\(.preset)"' "$SETTINGS"
    exit 0
    ;;
  *)
    sed -n '3,20p' "$0"
    exit 1
    ;;
esac

echo
echo "Next: chezmoi apply && rice aqua"
