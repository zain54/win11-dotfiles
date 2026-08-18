#!/bin/bash

#  Rice script
#  Author  :  jadetam (aquapaka)
#  Url     :  https://github.com/jade-tam/dotfiles
#  About   :  This file will configure and launch the rice.
#
#  Local changes (zain54 fork):
#    - Colours are owned by the wallpaper palette, not the theme. See
#      scripts/walsync.sh — it drives Zebar, Windows Terminal and VS Code from
#      whatever Wallpaper Engine is showing. A theme now only sets the Zebar
#      bar (layout + CSS), the terminal font, and VS Code fonts/icons.
#    - Wallpaper is owned by Wallpaper Engine, so set_desktop_wallpaper and
#      wackground.ps1 were removed along with the per-theme wallpaper folders.
#    - GlazeWM was uninstalled, so set_glazewm_config was removed.
#    - change_windows_lightdark_mode was already disabled upstream as buggy and
#      read a settings.json key that no longer exists, so it went too.
#
#  The `rice` zsh function wraps this script and runs `walsync sync` after it.

avaiableThemes=("aqua" "wasabi" "shuri" "jade" "tlinh")

usage() {
  printf "
Rice Script for apply a rice theme

Usage:
`basename $0`\t[aqua]  \t A playful, mysterious girl with eyes like shimmering aqua, her movements graceful and quick, full of curiosity and charm
\t[wasabi] \t Mysterious and alluring, with eyes like deep ocean blue and an aura of fire, she exudes both danger and enchantment
\t[shuri] \t A gentle presence in shades of purple, like twilight's soft embrace—quietly comforting, effortlessly lovely
\t[jade] \t Introspective and layered, a soul with raw edges, nostalgic warmth, and unspoken strength
\t[tlinh] \t Vibrant and dynamic, with rich colors and bold accents, she radiates energy and sophisticated elegance
"
}

# Set zebar config
set_zebar_theme() {
  echo "Applying zebar theme..."
  # Replace ~/.glzr/zebar/dotifle-bar folder with the one in the rice
  rm -rf ~/.glzr/zebar/dotfile-bar
  cp -r ./rices/$theme/dotfile-bar ~/.glzr/zebar/dotfile-bar
  # Restart Zebar
  echo "Restarting Zebar..."
  taskkill -IM zebar.exe -F > /dev/null 2>&1
  start zebar > /dev/null 2>&1 &
  echo "✅ Zebar theme applied!"
}

# Set VSCode fonts and icon theme
# NOTE: colours come from the wallpaper palette via the Wal Theme extension, so
# the per-theme JSON files intentionally no longer contain
# `workbench.colorTheme` or `workbench.colorCustomizations`.
set_vscode_theme() {
  echo "Applying VSCode theme..."
  echo "$(jq -s '.[0] * .[1]' ~/AppData/Roaming/Code/User/settings.json ./rices/$theme/vscode-theme-settings.json)" > tmp.json && mv tmp.json ~/AppData/Roaming/Code/User/settings.json
  echo "✅ VSCode theme applied!"
}

# Set windows terminal font
# NOTE: the colorScheme line was removed — `walsync term` sets the scheme from
# the wallpaper palette. Only the per-theme font is applied here.
set_windows_terminal_theme() {
  echo "Applying windows terminal font..."
  SETTING_FILE_PATH=$USERPROFILE\\AppData\\Local\\Packages\\Microsoft.WindowsTerminal_8wekyb3d8bbwe\\LocalState\\settings.json
  RICE_SETTING_FILE_PATH=./rices/$theme/settings.json
  jq ".profiles.defaults.font += input.windowsTerminalFont" $SETTING_FILE_PATH $RICE_SETTING_FILE_PATH > tmp.json && mv tmp.json $SETTING_FILE_PATH
  echo "✅ Windows terminal font applied!"
}

# Goes to this script location first
parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd "$parent_path"

for theme in "${avaiableThemes[@]}"; do
  if [[ "$1" == "$theme" ]]; then
    echo "⭐ Applying $theme theme ⭐"
    echo " "

    # # Apply configs
    set_windows_terminal_theme
    set_zebar_theme
    set_vscode_theme

    echo " "
    echo "⭐ Theme changing completed! ⭐"

    exit 0
  fi
done

usage
