#!/usr/bin/env bash
#
# strip-glazewm-bar.sh — remove the GlazeWM provider and the UI that depends
# on it from every theme's bar.html.
#
# Without GlazeWM running, Zebar's glazewm provider retries a dead IPC socket
# forever. The workspace dots and tiling-direction arrow render conditionally
# (`{output.glazewm && ...}`) so they'd vanish anyway — this removes the dead
# weight properly.
#
# Usage:
#   ./strip-glazewm-bar.sh preview   # show what would change
#   ./strip-glazewm-bar.sh apply     # do it (writes .bak files)
#   ./strip-glazewm-bar.sh restore   # put the .bak files back

set -euo pipefail

to_unix() { cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; }
SRC="$(to_unix "$(chezmoi source-path)")"
RICES="$SRC/dot_rice-manager/rices"
[ -d "$RICES" ] || { echo "Can't find $RICES"; exit 1; }

mapfile -t BARS < <(find "$RICES" -path "*/dotfile-bar/bar.html" | sort)
[ "${#BARS[@]}" -gt 0 ] || { echo "No bar.html found under $RICES"; exit 1; }

strip_one() {  # strip_one <file> <outfile>
  python3 - "$1" "$2" << 'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()

# 1. The provider registration line.
s = re.sub(r'^\s*glazewm:\s*\{\s*type:\s*"glazewm"\s*\},\s*\n', '', s, flags=re.M)

# 2. Any JSX block guarded by `output.glazewm && (...)`. These are balanced
#    brace groups, so count rather than regex the whole thing.
out, i = [], 0
while True:
    m = re.search(r'\{output\.glazewm &&', s[i:])
    if not m:
        out.append(s[i:])
        break
    start = i + m.start()
    out.append(s[i:start])
    depth, j = 0, start
    while j < len(s):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    i = j + 1
    # swallow the newline and indentation left behind
    while i < len(s) and s[i] in ' \t':
        i += 1
    if i < len(s) and s[i] == '\n':
        i += 1
s = ''.join(out)

open(dst, 'w', encoding='utf-8').write(s)
PY
}

case "${1:-}" in
  preview)
    for b in "${BARS[@]}"; do
      tmp="$(mktemp)"
      strip_one "$b" "$tmp"
      echo "=== ${b#$RICES/}"
      diff -u "$b" "$tmp" || true
      rm -f "$tmp"
    done
    ;;
  apply)
    for b in "${BARS[@]}"; do
      cp "$b" "$b.bak"
      tmp="$(mktemp)"
      strip_one "$b" "$tmp"
      mv "$tmp" "$b"
      echo "stripped ${b#$RICES/}  (backup: $(basename "$b").bak)"
    done
    echo
    echo "Next: chezmoi apply && rice aqua"
    ;;
  restore)
    for b in "${BARS[@]}"; do
      [ -f "$b.bak" ] || continue
      mv "$b.bak" "$b"
      echo "restored ${b#$RICES/}"
    done
    ;;
  *)
    sed -n '3,16p' "$0"
    exit 1
    ;;
esac
