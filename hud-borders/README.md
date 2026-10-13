# hud-borders

A Hyprland plugin that draws sci-fi HUD window frames: per-corner chamfers,
notches in the side edges, a slanted gauge on the bottom line, corner ticks, a
heavier bar on the top-right cut, and a diagonal hatch block in the
bottom-right corner.

## Why it exists

Hyprland's border renderer takes a single rounding radius for the whole window
(`decoration:rounding` + `decoration:rounding_power`), and `borders-plus-plus`
inherits that limit -- it calls `renderBorder()` once per ring with one radius.
So an asymmetric corner, or any ornament, is unreachable from configuration.

This plugin draws the frame with **cairo** into an ARGB surface and uploads it
as a texture (`CGLTexture` -> `renderTexture`), which is how `hyprbars` draws
its title bars. Cairo does arbitrary vector geometry, so corners can differ
from one another and carry decoration.

## Build

```sh
./rebuild.sh
```

The script locates Hyprland headers itself, in this order:

1. **Distro headers** — `hyprland.pc` on the default pkg-config path (the
   Arch package ships one). These are built from the same commit with the
   same dependency versions as the running binary, so they always match.
2. **hyprpm's cache** (`/var/cache/hyprpm/$USER/headersRoot`) — used only
   when the distro ships no headers (e.g. NixOS). The plugin ABI hash
   embeds Hyprland's commit hash *plus* the version strings of aquamarine,
   hyprutils, hyprgraphics, hyprcursor and hyprlang; hyprpm's cached
   headers carry the versions pinned in Hyprland's source, which can fall
   behind what the distro actually installed. The script detects that,
   rewrites the stale version macros in the cache, and only then builds.
   A cache whose commit hash differs from the running compositor is an
   error — `hyprpm update` is the only fix for that.

It also checks the plugin's load result afterwards and reports the remedy
instead of leaving you with a silent "reloaded" and an unloaded plugin.

Requires cairo and a C++23 compiler. (Only `hyprpm update` when told.)

## Install / load

Loaded at session start from `~/.config/hypr/autostart.lua`:

```lua
hl.exec_cmd("hyprctl plugin load " .. os.getenv("HOME") .. "/.local/src/hud-borders/hud-borders.so")
```

## Config

All keys live under `plugin:hud-borders:`. From Omarchy's Lua config:

```lua
hl.config({
  plugin = {
    hud_borders = {
      outer_thickness = 1,   -- thin outer hairline
      gap             = 3,   -- dark space between the two lines
      inner_thickness = 2,   -- main line

      col = {
        active         = "rgba(5ce4ffff)",
        inactive       = "rgba(0d3b4acc)",
        outer_active   = "rgba(0b86b3cc)",
        outer_inactive = "rgba(0d3b4a66)",
        mask           = "rgba(020d06f2)",
      },

      chamfer_top_left     = 10,
      chamfer_top_right    = 40,   -- the asymmetric one
      chamfer_bottom_right = 24,
      chamfer_bottom_left  = 10,   -- 0 leaves a corner square

      -- Notches stepped into the side edges at 45 degrees. Start and length
      -- are percentages of the window height (length includes both slopes);
      -- depth is in px, 0 = off.
      notch_right_start = 40, notch_right_length = 20, notch_right_depth = 0,
      notch_left_start  = 70, notch_left_length  = 15, notch_left_depth  = 0,

      corner_mask = true,
      -- col.mask above should match the window background.

      ticks       = true, tick_length = 16, tick_inset = 5,
      tab         = true, tab_length  = 34,   -- bar on the top-right cut
      hatch       = true, hatch_count = 3, hatch_size = 18,

      -- Slanted bar plus trailing slashes inside the bottom line, leaning
      -- like the bottom-right cut. gauge_start is a percentage of the width.
      -- gauge_fill stretches the bar until the last slash stops one
      -- gauge_gap short of that cut, and gauge_length is then ignored.
      gauge = false, gauge_fill = false, gauge_start = 60,
      gauge_height = 12, gauge_length = 72, gauge_inset = 2,
      gauge_stripes = 3, gauge_stripe_width = 10, gauge_gap = 4,
    },
  },
})
```

## Known limitations

- **Chamfers larger than `decoration:rounding` need the corner mask.** The frame
  is drawn over the window, but the window's own corners are rounded uniformly
  by Hyprland and a decoration cannot clip window content. `corner_mask` (on by
  default) paints `col.mask` into the cut so content does not show through.
  Set `col.mask` to match your window background; a mismatch shows up as a
  visible patch in the corner.
- **Resizing repaints the whole frame.** The texture is cached and only rebuilt
  when the size, focus or config changes -- but a live resize changes the size
  every frame, so each frame re-renders and re-uploads a full window-sized
  surface. Fine for tiled use; visible on a large floating window dragged by a
  corner. The fix is a 9-slice (fixed corner textures + `renderRect` edges).
- **Hyprland and its dependency libraries break it on update.** The plugin
  ABI hash includes the versions of aquamarine/hyprutils/hyprgraphics/
  hyprcursor/hyprlang, so any of them moving can stop the plugin from
  loading even when Hyprland itself is unchanged. Run `./rebuild.sh` after
  every update that touches any of those packages; it repairs a stale
  hyprpm header cache itself.

## Fallback

`borders-plus-plus` is still installed and enabled; the Matrix theme sets its
`add_borders = 0` so it draws nothing. The theme also sets
`general.border_size = 0`, since this plugin draws the thick inner line itself
and Hyprland's own border would otherwise trace a uniformly-chamfered path
across the asymmetric corners.

If this plugin ever fails to load, restore both in the theme:

```lua
general = { border_size = 2 },
plugin  = { borders_plus_plus = { add_borders = 2 } },
```
