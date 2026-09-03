-- White Rabbit: green console text inside a cyan HUD frame.
--
-- rounding_power controls the superellipse exponent used for corners:
-- 2.0 is a circular arc, >2 is a squircle, and 1.0 collapses the curve into
-- a straight 45-degree line -- a true chamfer. That is what gives the frame
-- its angled corners while costing far less window area than round corners.

local active_border_color = { colors = { "rgba(378999ff)", "rgba(06506bff)" }, angle = 45 }
local inactive_border_color = "rgba(0d3b4acc)"

hl.config({
  general = {
    -- hud-borders draws the entire frame, including the thick inner line. If
    -- Hyprland drew its own border too it would trace a uniformly-chamfered
    -- path across the asymmetric corners. The colours below still matter as a
    -- fallback: restore border_size = 2 if the plugin ever stops loading.
    border_size = 0,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  -- borders-plus-plus is kept installed as a fallback but draws nothing while
  -- hud-borders is loaded. Set add_borders back to 2 to return to it.
  plugin = {
    borders_plus_plus = {
      add_borders = 0,
    },

    -- hud-borders: our own plugin. Draws the whole frame in cairo, so corners
    -- can differ from one another and carry ornaments.
    hud_borders = {
      outer_thickness = 1,
      gap             = 3,
      inner_thickness = 2,

      col = {
        active         = "rgba(378999ff)",
        inactive       = "rgba(0d3b4acc)",
        outer_active   = "rgba(06506bcc)",
        outer_inactive = "rgba(0d3b4a66)",
        -- Painted into the corner cuts. Hyprland rounds window content
        -- uniformly and a decoration cannot clip it, so a chamfer deeper than
        -- decoration:rounding would otherwise show content in the cut.
        mask           = "rgba(020d06f2)",
      },

      chamfer_top_left     = 10,
      chamfer_top_right    = 40,
      chamfer_bottom_right = 24,
      chamfer_bottom_left  = 10,

      ticks       = true,
      tick_length = 16,
      tick_inset  = 5,

      tab         = true,
      tab_length  = 34,

      hatch       = true,
      hatch_count = 3,
      hatch_size  = 18,
    },
  },

  decoration = {
    rounding = 8,
    rounding_power = 1.0,

    -- Frosted glass, not a see-through window. The surface keeps a sliver of
    -- translucency so the backdrop still lights it, but the blur below is wide
    -- enough that what comes through is a diffuse wash rather than readable
    -- rain. Inactive windows used to be the worst offenders at 0.80.
    active_opacity = 0.94,
    inactive_opacity = 0.93,
    fullscreen_opacity = 1.0,

    blur = {
      enabled = true,
      -- Frosting is mostly these two. size widens the sample radius, passes
      -- spread it further each time; at 8/3 the rain glyphs behind a window
      -- were still legible, and legible backdrop is what stops a surface
      -- reading as glass.
      size = 4,
      passes = 1,
      new_optimizations = true,
      ignore_opacity = true,
      -- The grain in etched glass. Heavy blur on its own comes out as flat
      -- paint; a little noise is what puts a surface back on the pane.
      noise = 0.02,
      -- Sink the wallpaper back so the text keeps its contrast, and pull the
      -- little remaining structure toward the theme's green.
      brightness = 1.2,
      contrast = 1.1,
      vibrancy = 0.6,
      vibrancy_darkness = 0.0,
      -- Dropdowns and context menus are panes of the same glass.
      popups = true,
      popups_ignorealpha = 0.2,
    },

    -- Faint, even bloom. Kept low on purpose: a wide glow fills the dark
    -- spacer between the two border rings and the thin-outer/thick-inner
    -- pair stops reading as two lines.
    shadow = {
      enabled = true,
      range = 4,
      render_power = 4,
      color = "rgba(3789991a)",
      color_inactive = "rgba(00080410)",
    },
  },
})

-- The shell's surfaces -- bar, menu, notifications, OSD, the polkit card -- are
-- layer-shell, not windows, so decoration:blur never reaches them. Without
-- these rules they stay plainly see-through while every window around them is
-- glass, which is exactly the mismatch the frosting is meant to remove.
--
-- ignore_alpha is the important half: a layer surface spans its whole anchored
-- rectangle, most of which is fully transparent padding around a small card.
-- Blurring that too would hang a frosted slab across the screen, so anything
-- below 0.2 alpha is left alone and only the card itself frosts.
local glass_layers = table.concat({
  "omarchy-bar",
  "omarchy-menu",
  "omarchy-notifications",
  "omarchy-osd",
  "omarchy-polkit",
  "omarchy-reminders",
  "omarchy-clipboard",
  "omarchy-emojis",
  "omarchy-image-selector",
  "omarchy-keyboard-panel",
  "omarchy-network-qr",
}, "|")

hl.layer_rule({ match = { namespace = "^(" .. glass_layers .. ")$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(" .. glass_layers .. ")$" }, ignore_alpha = 0.2 })
-- Bar popouts (audio, network, battery) are popups of the bar surface.
hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur_popups = true })

-- The screensaver's digital rain (cycclon.rain) is a layer surface on Top
-- rather than Overlay, so that omarchy-crt keeps passing over it and the rain
-- picks up the same scanlines and vignette as everything else. Top's only
-- other tenant is the bar, and a screensaver that leaves the bar showing is
-- not a screensaver, so `order` has to lift the rain over it.
--
-- Note the sign: on 0.56.2 a *lower* order draws nearer the top of its layer,
-- which is the opposite of the way the option reads. Measured, not assumed --
-- order = 1 left the bar sitting on top of the rain.
--
-- The phosphor glow needs no rule at all: it is a screen shader and receives
-- the finished frame, rain included.
hl.layer_rule({ match = { namespace = "^(omarchy-rain)$" }, order = -1 })
