#!/usr/bin/env bash
# Rebuild hud-borders against the running Hyprland and reload it.
# Run this after every Hyprland update -- the plugin links against Hyprland's
# internal API, so a version bump will refuse to load until it is rebuilt.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

HEADERS="/var/cache/hyprpm/$USER/headersRoot/share/pkgconfig"
if [[ ! -d $HEADERS ]]; then
  echo "Hyprland headers missing. Run:  hyprpm update" >&2
  exit 1
fi

echo "Hyprland: $(hyprctl version | head -1)"

export PKG_CONFIG_PATH="$HEADERS"
make clean >/dev/null 2>&1 || true
make

hyprctl plugin unload "$PWD/hud-borders.so" >/dev/null 2>&1 || true
hyprctl plugin load "$PWD/hud-borders.so"
echo "reloaded."
