#!/usr/bin/env bash
# Install the White Rabbit theme into a running Omarchy session.
#
# What this does, in order:
#   1. copies the theme files at the repo root -> ~/.config/omarchy/themes/white-rabbit/
#      (hyprland.lua.example and foot.ini.example are installed as the real
#      hyprland.lua and foot.ini)
#   2. copies plugins/cycclon.* -> ~/.config/omarchy/plugins/cycclon.*/
#      and enables them in the running shell; cycclon.menu, which replaces
#      Omarchy's built-in menu, is asked about separately
#   3. optionally builds hud-borders/ (a native Hyprland plugin) and wires it
#      into ~/.config/hypr/autostart.lua
#   4. optionally installs the White Rabbit cursors to
#      ~/.local/share/icons/WhiteRabbit
#   5. applies the theme and restarts the shell
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
MENU_ID="cycclon.menu"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
ASSUME_YES=0
SKIP_HUD_BORDERS=0
SKIP_MENU=0
SKIP_CURSORS=0
CURSOR_THEME="WhiteRabbit"
CURSOR_DST="$HOME/.local/share/icons/$CURSOR_THEME"

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-hud-borders) SKIP_HUD_BORDERS=1 ;;
    --no-menu) SKIP_MENU=1 ;;
    --no-cursors) SKIP_CURSORS=1 ;;
    --help|-h)
      echo "Usage: ./install.sh [--yes] [--no-hud-borders] [--no-menu] [--no-cursors]"
      echo "  --yes              don't prompt for confirmation"
      echo "  --no-hud-borders   skip the native window-frame plugin entirely"
      echo "  --no-menu          keep Omarchy's built-in menu"
      echo "  --no-cursors       keep your current mouse cursors"
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
rest of your desktop), optionally a fourth that replaces Omarchy's menu, and,
optionally, a native Hyprland plugin built from C++
source and loaded with `hyprctl plugin load`. Review hyprland.lua.example,
plugins/ and hud-borders/ before continuing if you have not already.
EOF
confirm "Continue?" || exit 1

# --- 1. theme --------------------------------------------------------------

# The theme files live at the repo root so `omarchy theme install` finds them.
# That route stages only the palette and backgrounds: Omarchy drops
# hyprland.lua and terminal configs from a git-cloned theme, which is why the
# repo carries them as *.example. This installer copies them in under their
# real names, into a directory with no .git, so they take effect.
THEME_FILES=(backgrounds colors.toml gtk.css gtk4.css icons.theme preview.png shell.*.toml)

if [[ $ROOT -ef $THEME_DST ]]; then
  fail "this checkout IS $THEME_DST (installed via 'omarchy theme install'?). Clone the repo somewhere else, e.g. ~/.local/src, and run install.sh from there -- it replaces that directory."
fi

note "Installing theme to $THEME_DST"
if [[ -d $THEME_DST/.git ]]; then
  warn "replacing the git clone found at $THEME_DST"
  warn "(a theme installed via 'omarchy theme install' drops hyprland.lua and"
  warn " foot.ini for safety -- this installer needs those staged, so it always"
  warn " replaces the theme directory outright rather than layering onto that clone)"
fi
rm -rf "$THEME_DST"
mkdir -p "$THEME_DST"
( cd "$ROOT" && cp -r "${THEME_FILES[@]}" "$THEME_DST"/ )
cp "$ROOT/hyprland.lua.example" "$THEME_DST/hyprland.lua"
cp "$ROOT/foot.ini.example" "$THEME_DST/foot.ini"

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

# The menu is a copy of Omarchy's own menu plugin with the HUD frame and
# animations added. Enabling a plugin whose manifest names a clonedFrom source
# swaps it in for that built-in; disabling it swaps the built-in back.
if (( SKIP_MENU )); then
  note "Skipping $MENU_ID (--no-menu)"
elif confirm "Replace Omarchy's Super+Space menu with the White Rabbit one? (a snapshot of Omarchy's menu code with the HUD frame and animations; './uninstall.sh' or 'omarchy plugin disable $MENU_ID' restores the built-in menu)"; then
  note "Installing $MENU_ID"
  rm -rf "${PLUGINS_DST:?}/$MENU_ID"
  cp -r "$ROOT/plugins/$MENU_ID" "$PLUGINS_DST/$MENU_ID"
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy plugin enable "$MENU_ID" >/dev/null 2>&1 || warn "could not enable $MENU_ID -- run: omarchy plugin enable $MENU_ID"
else
  note "Skipping $MENU_ID"
fi

# --- 3. hud-borders (optional, native plugin) -------------------------------

HUD_BUILT=0
if (( SKIP_HUD_BORDERS )); then
  note "Skipping hud-borders (--no-hud-borders)"
elif confirm "Build and load hud-borders, the HUD window-frame plugin? (needs a C++23 toolchain, cairo, and Hyprland's headers; without it every window has no border)"; then
  # Arch's hyprland package ships its headers (hyprland.pc); hyprpm's cache is
  # only a fallback for distros that don't, and newer packages drop hyprpm.
  HYPRPM_PC="/var/cache/hyprpm/$USER/headersRoot/share/pkgconfig"
  have_headers() { pkg-config --exists hyprland 2>/dev/null || [[ -d $HYPRPM_PC ]]; }
  if ! have_headers && command -v hyprpm >/dev/null 2>&1; then
    if confirm "Hyprland headers not found -- run 'hyprpm update' now? (downloads and builds against your exact Hyprland version)"; then
      hyprpm update
    fi
  fi
  if have_headers; then
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
    warn "Hyprland headers not found; skipping the build. Install your distro's"
    warn "Hyprland development headers (hyprland.pc), then run 'hud-borders/rebuild.sh'."
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
  warn "hud-borders is not loaded. hyprland.lua sets border_size = 0 because it"
  warn "expects hud-borders to draw the frame instead -- without it every window"
  warn "will have NO visible border at all. Either re-run this installer, run"
  warn "hud-borders/rebuild.sh by hand later, or open $THEME_DST/hyprland.lua"
  warn "and set general.border_size = 2 to fall back to Hyprland's plain border."
fi

# --- 4. cursors (optional) ---------------------------------------------------

# A plain XCursor theme, prebuilt from cursors/gen.py. hyprland.lua selects it
# with XCURSOR_THEME; GTK apps read the gsettings key instead.
CURSORS_INSTALLED=0
if (( SKIP_CURSORS )); then
  note "Skipping cursors (--no-cursors)"
elif confirm "Install the White Rabbit mouse cursors? (cyan line-art pointer, hand, text beam and the rest)"; then
  note "Installing cursors to $CURSOR_DST"
  rm -rf "$CURSOR_DST"
  mkdir -p "$(dirname "$CURSOR_DST")"
  cp -a "$ROOT/cursors/$CURSOR_THEME" "$CURSOR_DST"
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" || true
  fi
  CURSORS_INSTALLED=1
else
  note "Skipping cursors"
fi

# --- 5. apply ----------------------------------------------------------------

note "Applying the theme"
omarchy theme set "$THEME_NAME"
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
if (( CURSORS_INSTALLED )); then
  hyprctl setcursor "$CURSOR_THEME" "${XCURSOR_SIZE:-24}" >/dev/null 2>&1 || true
fi

cat <<EOF

Done. White Rabbit is applied.

  omarchy-shell rain status     -- screensaver state
  omarchy-shell crt status      -- CRT overlay state
  omarchy-shell glow status     -- phosphor glow state
  omarchy-shell rain word "LINUX"   -- force a word to align next

See README.md for every setting and the full IPC surface.
EOF
