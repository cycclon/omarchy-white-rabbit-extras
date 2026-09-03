#!/usr/bin/env bash
# Install the White Rabbit theme into a running Omarchy session.
#
# What this does, in order:
#   1. copies theme/            -> ~/.config/omarchy/themes/whiterabbit/
#   2. copies plugins/cycclon.* -> ~/.config/omarchy/plugins/cycclon.*/
#      and enables them in the running shell
#   3. optionally builds hud-borders/ (a native Hyprland plugin) and wires it
#      into ~/.config/hypr/autostart.lua
#   4. applies the theme and restarts the shell
#
# Safe to re-run: every step overwrites its own previous copy rather than
# merging, so running this again after `git pull` is how you update.
#
# This script edits files outside this repo (your Omarchy config) and, if you
# opt in, builds and loads a native compiler plugin into a running Hyprland
# session. Read it before running it, the same way you would before adding
# any other unsandboxed Omarchy plugin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="white-rabbit"
THEME_DST="$HOME/.config/omarchy/themes/$THEME_NAME"
PLUGINS_DST="$HOME/.config/omarchy/plugins"
PLUGIN_IDS=(cycclon.crt cycclon.glow cycclon.rain)
AUTOSTART="$HOME/.config/hypr/autostart.lua"
ASSUME_YES=0
SKIP_HUD_BORDERS=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-hud-borders) SKIP_HUD_BORDERS=1 ;;
    --help|-h)
      echo "Usage: ./install.sh [--yes] [--no-hud-borders]"
      echo "  --yes              don't prompt for confirmation"
      echo "  --no-hud-borders   skip the native window-frame plugin entirely"
      exit 0
      ;;
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

note()  { echo "-- $*"; }
warn()  { echo "!! $*" >&2; }
fail()  { echo "xx $*" >&2; exit 1; }

command -v omarchy      >/dev/null 2>&1 || fail "omarchy CLI not found -- this installer is for Omarchy Linux"
command -v hyprctl       >/dev/null 2>&1 || fail "hyprctl not found -- is Hyprland running?"
command -v omarchy-shell >/dev/null 2>&1 || fail "omarchy-shell not found"

if ! omarchy-shell shell ping >/dev/null 2>&1; then
  fail "omarchy-shell is not responding -- log into a Hyprland session first"
fi

cat <<'EOF'
White Rabbit installs three unsandboxed Quickshell plugins (they run as plain
QML inside your existing omarchy-shell process, with the same access as the
rest of your desktop) and, optionally, a native Hyprland plugin built from C++
source and loaded with `hyprctl plugin load`. Review the code in theme/,
plugins/ and hud-borders/ before continuing if you have not already.
EOF
confirm "Continue?" || exit 1

# --- 1. theme --------------------------------------------------------------

note "Installing theme to $THEME_DST"
if [[ -d $THEME_DST/.git ]]; then
  warn "removing a .git directory found in an existing $THEME_DST"
  warn "(a theme installed via 'omarchy theme install' silently drops hyprland.lua"
  warn " and foot.ini for safety -- this installer needs those staged, so it always"
  warn " replaces the theme directory outright rather than layering onto that clone)"
fi
rm -rf "$THEME_DST"
mkdir -p "$THEME_DST"
cp -r "$ROOT"/theme/. "$THEME_DST"/

# --- 2. quickshell plugins ---------------------------------------------------

note "Installing plugins: ${PLUGIN_IDS[*]}"
mkdir -p "$PLUGINS_DST"
for id in "${PLUGIN_IDS[@]}"; do
  rm -rf "${PLUGINS_DST:?}/$id"
  cp -r "$ROOT/plugins/$id" "$PLUGINS_DST/$id"
done

omarchy-shell shell rescanPlugins >/dev/null
for id in "${PLUGIN_IDS[@]}"; do
  omarchy plugin enable "$id" >/dev/null 2>&1 || true
done

# --- 3. hud-borders (optional, native plugin) -------------------------------

HUD_BUILT=0
if (( SKIP_HUD_BORDERS )); then
  note "Skipping hud-borders (--no-hud-borders)"
elif confirm "Build and load hud-borders, the HUD window-frame plugin? (needs a C++23 toolchain, cairo, and Hyprland's headers; without it every window has no border)"; then
  HEADERS="/var/cache/hyprpm/$USER/headersRoot/share/pkgconfig"
  if [[ ! -d $HEADERS ]]; then
    if confirm "Hyprland headers not found -- run 'hyprpm update' now? (downloads and builds against your exact Hyprland version)"; then
      hyprpm update
    fi
  fi
  if [[ -d $HEADERS ]]; then
    note "Building hud-borders"
    if ( cd "$ROOT/hud-borders" && ./rebuild.sh ); then
      HUD_BUILT=1
    else
      warn "hud-borders failed to build -- see the errors above."
      warn "Common cause: your Hyprland version's headers don't match this plugin's use"
      warn "of Hyprland's internal API. It links against Hyprland internals, not a"
      warn "stable ABI, so a point release can require changes -- check the repo issues."
    fi
  else
    warn "Hyprland headers still missing; skipping the build. Run 'hyprpm update' and"
    warn "then 'hud-borders/rebuild.sh' yourself later."
  fi
else
  note "Skipping hud-borders"
fi

if (( HUD_BUILT )); then
  HOOK="hl.exec_cmd(\"hyprctl plugin load $ROOT/hud-borders/hud-borders.so\")"
  if [[ -f $AUTOSTART ]] && grep -qF "hud-borders.so" "$AUTOSTART"; then
    note "$AUTOSTART already loads a hud-borders.so -- leaving it alone"
    note "(if it points at a different path, edit that line to: $HOOK)"
  else
    note "Adding a load hook to $AUTOSTART"
    mkdir -p "$(dirname "$AUTOSTART")"
    [[ -f $AUTOSTART ]] && cp "$AUTOSTART" "$AUTOSTART.bak.$(date +%s)"
    {
      [[ -f $AUTOSTART ]] && cat "$AUTOSTART"
      cat <<EOF

-- Added by the White Rabbit theme installer.
hl.on("hyprland.start", function()
  $HOOK
end)
EOF
    } > "$AUTOSTART.new"
    mv "$AUTOSTART.new" "$AUTOSTART"
  fi
  hyprctl plugin load "$ROOT/hud-borders/hud-borders.so" >/dev/null 2>&1 || true
else
  warn "hud-borders is not loaded. theme/hyprland.lua sets border_size = 0 and"
  warn "add_borders = 0 because it expects hud-borders to draw the frame instead --"
  warn "without it every window will have NO visible border at all. Either re-run"
  warn "this installer, run hud-borders/rebuild.sh by hand later, or open"
  warn "$THEME_DST/hyprland.lua and set general.border_size = 2 and"
  warn "plugin.borders_plus_plus.add_borders = 2 to fall back to plain borders."
fi

# --- 4. apply ----------------------------------------------------------------

note "Applying the theme"
omarchy theme set "$THEME_NAME"
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true

cat <<EOF

Done. White Rabbit is applied.

  omarchy-shell rain status     -- screensaver state
  omarchy-shell crt status      -- CRT overlay state
  omarchy-shell glow status     -- phosphor glow state
  omarchy-shell rain word "LINUX"   -- force a word to align next

See README.md for every setting and the full IPC surface.
EOF
