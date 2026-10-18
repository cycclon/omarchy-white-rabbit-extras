#!/usr/bin/env bash
# Remove everything install.sh added: the theme, the Quickshell plugins
# (disabling the menu one brings Omarchy's built-in menu back), and the
# hud-borders autostart hook. Does not touch hud-borders.so
# itself or this checkout -- delete the cloned repo yourself if you're done
# with it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="white-rabbit"
THEME_DST="$HOME/.config/omarchy/themes/$THEME_NAME"
PLUGINS_DST="$HOME/.config/omarchy/plugins"
PLUGIN_IDS=(cycclon.crt cycclon.glow cycclon.rain cycclon.menu)
AUTOSTART="$HOME/.config/hypr/autostart.lua"
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --help|-h) echo "Usage: ./uninstall.sh [--yes]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

confirm() {
  local prompt="$1"
  (( ASSUME_YES )) && return 0
  if command -v gum >/dev/null 2>&1; then
    gum confirm "$prompt"
  else
    read -r -p "$prompt [y/N] " reply
    [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
  fi
}

note() { echo "-- $*"; }

current_theme="$(omarchy theme current 2>/dev/null || true)"
if [[ $current_theme == "$THEME_NAME" ]]; then
  echo "White Rabbit is your active theme. Switch away from it first:"
  echo "  omarchy theme set <another-theme>"
  exit 1
fi

confirm "Remove the White Rabbit theme, its plugins, and the hud-borders autostart hook?" || exit 1

note "Removing plugins"
for id in "${PLUGIN_IDS[@]}"; do
  if [[ -d "$PLUGINS_DST/$id" ]]; then
    omarchy plugin disable "$id" >/dev/null 2>&1 || true
    rm -rf "${PLUGINS_DST:?}/$id"
  fi
done
command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

note "Removing theme directory"
rm -rf "$THEME_DST"

if [[ -f $AUTOSTART ]] && grep -qF "hud-borders.so" "$AUTOSTART"; then
  note "Removing the hud-borders hook from $AUTOSTART"
  cp "$AUTOSTART" "$AUTOSTART.bak.$(date +%s)"
  # Drop the exact hl.on(...) block the installer appended. Anything you added
  # by hand near it is left alone; a plain marker-line delete would risk eating
  # unrelated autostart entries typed above or below it.
  perl -0pi -e 's/\n-- Added by the White Rabbit theme installer\.\nhl\.on\("hyprland\.start", function\(\)\n  hl\.exec_cmd\("hyprctl plugin load [^\n]*"\)\nend\)\n//' "$AUTOSTART"
fi

if hyprctl plugin list 2>/dev/null | grep -q "hud-borders" && [[ -f "$ROOT/hud-borders/hud-borders.so" ]]; then
  note "Unloading hud-borders from the running session"
  hyprctl plugin unload "$ROOT/hud-borders/hud-borders.so" >/dev/null 2>&1 || \
    echo "   Couldn't unload automatically -- run: hyprctl plugin unload $ROOT/hud-borders/hud-borders.so"
fi

command -v omarchy >/dev/null 2>&1 && { omarchy restart shell >/dev/null 2>&1 || true; }

echo "Done. general.border_size belonged to"
echo "White Rabbit's own hyprland.lua, so nothing to restore there -- your next"
echo "theme's own settings apply as soon as you switch to it."
