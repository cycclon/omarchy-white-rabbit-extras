#!/usr/bin/env bash
# Rebuild hud-borders against the running Hyprland and reload it.
# Run this after every update that touches Hyprland or any of its dependency
# libraries -- the plugin links against Hyprland's internal API, and the ABI
# check embeds a hash of the commit hash plus the dependency version strings,
# so the plugin refuses to load until it is rebuilt against matching headers.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

note() { echo "-- $*"; }
warn() { echo "!! $*" >&2; }
fail() { echo "xx $*" >&2; exit 1; }

command -v pkg-config >/dev/null 2>&1 || fail "pkg-config not found"
command -v hyprctl    >/dev/null 2>&1 || fail "hyprctl not found -- is Hyprland running?"

note "Hyprland: $(hyprctl version | head -1)"

# The plugin ABI hash is GIT_COMMIT_HASH plus the versions of aquamarine,
# hyprutils, hyprgraphics, hyprcursor and hyprlang. Those dependencies can be
# upgraded by the distro without the Hyprland version changing, and then
# hyprpm's cached headers -- which carry the versions pinned in Hyprland's own
# source -- build a plugin whose hash doesn't match the running compositor
# even though the API surface is identical. hyprpm itself doesn't catch this:
# it will happily report "Headers up to date" against its own stale hash.
#
# The headers the distro ships with the Hyprland package (hyprland.pc on the
# default pkg-config path) are built from the same commit with the same
# dependency versions as the running binary, so prefer those. Only fall back
# to hyprpm's cache when the distro doesn't ship headers (e.g. NixOS), and
# then verify the cache's version macros against the installed libraries.

CACHE_ROOT="/var/cache/hyprpm/$USER"
CACHE_PC="$CACHE_ROOT/headersRoot/share/pkgconfig"
CACHE_VERSION_H="$CACHE_ROOT/headersRoot/include/hyprland/src/version.h"

strip_patch() {
    # mirrors Hyprland's PluginAPI.hpp stripPatch: drop the last ".x" segment
    local v=$1
    [[ $v == *.* ]] && v=${v%.*}
    printf %s "$v"
}

check_stale_cache() {
    [[ -f $CACHE_VERSION_H ]] || fail "hyprpm cache has no version.h -- run: hyprpm update"

    # If the cached headers are for a different Hyprland commit, only
    # `hyprpm update` can fix that; don't try to patch across commits.
    local run_hash cache_hash dep sys cached
    run_hash="$(hyprctl version | grep -oE '[0-9a-f]{40}' | head -1)"
    cache_hash="$(grep -m1 '^#define GIT_COMMIT_HASH' "$CACHE_VERSION_H" | grep -oE '[0-9a-f]{40}')"
    if [[ -n $run_hash && -n $cache_hash && $run_hash != "$cache_hash" ]]; then
        fail "hyprpm cache is for Hyprland commit ${cache_hash:0:7}, running is ${run_hash:0:7} -- run: hyprpm update"
    fi

    for dep in aquamarine hyprutils hyprgraphics hyprcursor hyprlang; do
        sys="$(pkg-config --modversion "$dep" 2>/dev/null)" || continue
        cached="$(sed -n "s/^#define ${dep^^}_VERSION \"\([^\"]*\)\"$/\1/p" "$CACHE_VERSION_H")"
        [[ -n $cached ]] || continue
        if [[ $(strip_patch "$cached") != "$(strip_patch "$sys")" ]]; then
            if [[ -w $CACHE_VERSION_H ]]; then
                sed -i "s/^#define ${dep^^}_VERSION .*/#define ${dep^^}_VERSION \"$sys\"/" "$CACHE_VERSION_H"
                note "hyprpm cache pins $dep $cached but the system has $sys -- patched version.h"
            else
                fail "hyprpm cache pins $dep $cached but the system has $sys; the ABI hash includes
these version strings, so a build against the cache will not load. Sync it with:

  sudo sed -i 's/^#define ${dep^^}_VERSION .*/#define ${dep^^}_VERSION \"$sys\"/' $CACHE_VERSION_H

then re-run this script."
            fi
        fi
    done
}

if env -u PKG_CONFIG_PATH pkg-config --exists hyprland; then
    # Distro headers are always in lockstep with the running binary. Unset
    # PKG_CONFIG_PATH so make's pkg-config can't resolve hyprland to a stale
    # hyprpm cache that the user may have exported.
    unset PKG_CONFIG_PATH
    note "headers: distro hyprland.pc ($(pkg-config --modversion hyprland))"
else
    [[ -d $CACHE_PC ]] || fail "no hyprland.pc on the default pkg-config path and no hyprpm cache -- install your distro's Hyprland headers (or run 'hyprpm update' if your Hyprland still ships hyprpm)"
    export PKG_CONFIG_PATH="$CACHE_PC"
    note "headers: hyprpm cache (no distro hyprland.pc found)"
    check_stale_cache
fi

make clean >/dev/null 2>&1 || true
make

hyprctl plugin unload "$PWD/hud-borders.so" >/dev/null 2>&1 || true
LOAD_OUT="$(hyprctl plugin load "$PWD/hud-borders.so" 2>&1)" || true
if [[ $LOAD_OUT == *"could not be loaded"* ]]; then
    warn "$LOAD_OUT"
    if [[ $LOAD_OUT == *"Version mismatch"* ]]; then
        warn "the headers used for the build do not match the running Hyprland's ABI"
        warn "hash (commit + dependency versions). If you built against the hyprpm"
        warn "cache, re-run this script after its version.h is synced; if this"
        warn "persists, run 'hyprpm update' and then this script again."
    fi
    exit 1
fi
note "reloaded."
