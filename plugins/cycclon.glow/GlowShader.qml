// Kid's Story phosphor glow for the White Rabbit theme.
//
// The CRT overlay paints generic bands above every window, but it cannot add
// light: alpha blending only darkens. The film's glow -- bright glyphs bleeding
// green that smears sideways along the scanlines -- and the beam warp (each
// scanline band of a glyph displaced a hair) both need to *add* light to the
// finished screen, so they live in Hyprland's decoration:screen_shader, which
// receives the fully rendered frame.
//
// This plugin owns that slot while the White Rabbit theme is active:
//
//   - writes the shader file (~/.local/state/omarchy/whiterabbit-glow.frag) with a
//     PARAMS block baked in
//   - points decoration:screen_shader at it while (theme is whiterabbit AND enabled)
//   - clears the option when the theme changes or the effect is toggled off,
//     so other themes are never tinted
//   - `omarchy-shell glow set name value` rewrites the params and re-applies,
//     which recompiles the shader live
//
// The CRT overlay plugin is untouched: toggle either, or run both together --
// they stack (scanlines/haze/vignette from the overlay, bloom/warp here).
import QtQuick
import Quickshell
import Quickshell.Io
import "./settings.js" as Settings

Item {
  id: root

  // --- theme gate ----------------------------------------------------------

  property bool matrixTheme: false

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.matrixTheme = text().trim() === "white-rabbit"
    onLoadFailed: root.matrixTheme = false
  }

  // --- tuning --------------------------------------------------------------

  // Defaults match the film still: a clear but not flooding bloom, a hair of
  // warp. PITCH should mirror the CRT overlay's pitch so glow and lines agree.
  property real bloom: 0.9       // glow strength (0 = off, 2 = heavy)
  property real warp: 0.35       // band waver amplitude in px (0 = off)
  property real pitch: 3.0       // rows per scanline band
  property real threshold: 0.20  // green+bright cutoff for what blooms
  property real grain: 0.35      // per-glyph glow unevenness (0 = even, 1 = wild)
  property real cell: 15.0       // glyph cell height in px -- grain grid scale
  property bool enabled: true

  property string shaderPath: Quickshell.env("HOME") + "/.local/state/omarchy/whiterabbit-glow.frag"
  property bool applied: false

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/glow-settings.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.saveSettings()
  }

  function loadSettings(raw) {
    try {
      var s = JSON.parse(raw)
      if (Settings.num(s.bloom)) bloom = Settings.clamp(s.bloom, 0, 3)
      if (Settings.num(s.warp)) warp = Settings.clamp(s.warp, 0, 3)
      if (Settings.num(s.pitch)) pitch = Settings.clamp(s.pitch, 2, 8)
      if (Settings.num(s.threshold)) threshold = Settings.clamp(s.threshold, 0, 1)
      if (Settings.num(s.grain)) grain = Settings.clamp(s.grain, 0, 2)
      if (Settings.num(s.cell)) cell = Settings.clamp(s.cell, 6, 60)
      if (typeof s.enabled === "boolean") enabled = s.enabled
    } catch (e) {
      console.warn("glow: bad settings json:", e)
    }
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({
      bloom: bloom, warp: warp, pitch: pitch,
      threshold: threshold, grain: grain, cell: cell, enabled: enabled
    }, null, 2) + "\n")
  }

  function setParam(name, value) {
    var v = Number(value)
    if (!isFinite(v)) return "bad value: " + value
    switch (name) {
      case "bloom":     bloom = Settings.clamp(v, 0, 3); break
      case "warp":      warp = Settings.clamp(v, 0, 3); break
      case "pitch":     pitch = Settings.clamp(v, 2, 8); break
      case "threshold": threshold = Settings.clamp(v, 0, 1); break
      case "grain":     grain = Settings.clamp(v, 0, 2); break
      case "cell":      cell = Settings.clamp(v, 6, 60); break
      default: return "unknown param: " + name + " (bloom, warp, pitch, threshold, grain, cell)"
    }
    saveSettings()
    return name + " = " + Settings.fmt(root[name])
  }

  // --- shader file ---------------------------------------------------------

  function shaderSource() {
    return shaderTemplate
      .replace("/*BLOOM*/", bloom.toFixed(3))
      .replace("/*WARP*/", warp.toFixed(3))
      .replace("/*PITCH*/", pitch.toFixed(1))
      .replace("/*THRESH*/", threshold.toFixed(3))
      .replace("/*GRAIN*/", grain.toFixed(3))
      .replace("/*CELL*/", cell.toFixed(1))
  }

  // Hyprland only reloads the shader when the option VALUE changes -- editing
  // the file in place and re-pointing the same path is a no-op at runtime.
  // So params are baked into two alternating files and the option flips
  // between them; every apply() changes the option value and forces a
  // recompile.
  readonly property var shaderPaths: [
    Quickshell.env("HOME") + "/.local/state/omarchy/whiterabbit-glow-a.frag",
    Quickshell.env("HOME") + "/.local/state/omarchy/whiterabbit-glow-b.frag"
  ]

  FileView {
    id: shaderFileA
    path: root.shaderPaths[0]
    printErrors: false
  }

  FileView {
    id: shaderFileB
    path: root.shaderPaths[1]
    printErrors: false
  }

  // Legacy single file: keep the old path current so anything referencing it
  // (docs, the state dir listing) still shows the live params.
  FileView {
    id: shaderFileLegacy
    path: root.shaderPath
    printErrors: false
  }

  // --- applying ------------------------------------------------------------

  Process {
    id: hyprctl
    command: ["hyprctl", "eval", ""]
    stdout: StdioCollector { }
  }

  // The file Hyprland is currently loading ("" when its screen_shader is
  // clear). Every apply must END on the OTHER path: Hyprland only recompiles
  // when the option value changes, so re-pointing at the same file -- even
  // with new content on disk -- is a no-op.
  property string liveShaderPath: ""

  function apply() {
    var want = matrixTheme && enabled
    if (want) {
      // Target is whichever file is not currently loaded; if none loaded,
      // either file works.
      var target = shaderPaths[0]
      if (liveShaderPath === shaderPaths[0]) target = shaderPaths[1]
      // Write BOTH files and block until each is on disk BEFORE re-pointing
      // Hyprland: it validates the path synchronously on the keyword, so a
      // dangling path here would pop the "Failed to check screen shader
      // path" error bar. The waitForJob calls close the write race.
      var src = shaderSource()
      shaderFileA.setText(src);  shaderFileA.waitForJob()
      shaderFileB.setText(src);  shaderFileB.waitForJob()
      shaderFileLegacy.setText(src); shaderFileLegacy.waitForJob()
      if (!shaderFileA.loaded || !shaderFileB.loaded) {
        console.warn("glow: shader files not written, skipping apply")
        return
      }
      hyprctl.command = ["hyprctl", "eval",
        "hl.config({ decoration = { screen_shader = \"" + target + "\" } })"]
      liveShaderPath = target
    } else if (liveShaderPath !== "") {
      hyprctl.command = ["hyprctl", "eval",
        "hl.config({ decoration = { screen_shader = \"\" } })"]
      liveShaderPath = ""
    }
    hyprctl.running = false
    hyprctl.running = true
    applied = want
  }

  onMatrixThemeChanged: apply()
  onEnabledChanged: apply()
  Component.onCompleted: applyTimer.start()

  // Small delay at startup: Hyprland's lua config must be in place before we
  // touch the option, and writing the shader file right away is fine.
  Timer {
    id: applyTimer
    interval: 1500
    onTriggered: root.apply()
  }

  // --- IPC -----------------------------------------------------------------

  IpcHandler {
    target: "glow"

    function toggle(): string {
      // Must qualify: IpcHandler has its own `enabled` property — an
      // unqualified assignment here flips the handler itself off and
      // deregisters the whole IPC target.
      root.enabled = !root.enabled
      saveSettings()
      return root.enabled ? "phosphor glow on" : "phosphor glow off"
    }

    function status(): string {
      if (!matrixTheme) return "inactive (theme is not White Rabbit)"
      return root.enabled
        ? "on -- bloom " + fmt(bloom) + ", warp " + fmt(warp)
          + ", pitch " + fmt(pitch) + ", threshold " + fmt(threshold)
          + ", grain " + fmt(grain) + ", cell " + fmt(cell)
        : "off"
    }

    function set(name: string, value: string): string {
      var r = setParam(name, value)
      if (r.startsWith("unknown") || r.startsWith("bad")) return r
      apply()
      return r
    }

    function reset(): string {
      bloom = 0.9; warp = 0.35; pitch = 3.0; threshold = 0.20
      grain = 0.35; cell = 15.0
      saveSettings(); apply()
      return "glow settings reset to defaults"
    }
  }

  function fmt(n) {
    return String(Math.round(n * 1000) / 1000)
  }

  // --- shader template -----------------------------------------------------

  // The /*NAME*/ holes are the baked-in tunables. #defines must come after
  // #version, so the block sits below the declarations.
  readonly property string shaderTemplate: `#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform vec2 fullSize;

layout(location = 0) out vec4 fragColor;

// ---BEGIN PARAMS--- (baked by omarchy.glow; tune via omarchy-shell glow set)
#define BLOOM   /*BLOOM*/ // glow strength: 0 off, 0.6 subtle, 1 film default, 2 heavy
#define WARP    /*WARP*/  // scanline band waver amplitude in pixels: 0 off
#define PITCH   /*PITCH*/ // rows per scanline band (match the CRT overlay's pitch)
#define THRESH  /*THRESH*/ // green+bright cutoff for what blooms
#define GRAIN   /*GRAIN*/ // per-glyph glow unevenness: 0 even, 0.35 film default
#define CELL    /*CELL*/  // glyph cell height in px -- grain grid scale
// ---END PARAMS---

const vec3 PHOSPHOR = vec3(0.10, 0.72, 0.27);

// Cheap deterministic hash: one glow variance per glyph cell, stable frame to
// frame so letters flicker only as slowly as their cell pattern, never per
// pixel of travel.
float hash21(vec2 p) {
  p = fract(p * vec2(233.34, 851.73));
  p += dot(p, p + 23.45);
  return fract(p.x * p.y);
}

// Per-sample bloom gate: how much a pixel counts as a phosphor light source.
// Bright and green-DOMINANT only -- terminal text and lit HUD. Requiring the
// green channel to lead the others is what keeps white pages and photos out:
// white has equal channels, so it saturates instead of tinting.
float srcMask(vec3 c) {
  float luma = dot(c, vec3(0.299, 0.587, 0.114));
  float bright = clamp((c.g - THRESH) / max(1.0 - THRESH, 0.001), 0.0, 1.0);
  float dom = clamp((c.g - max(c.r, c.b)) * 4.0, 0.0, 1.0);
  return pow(luma * bright * dom + 0.0001, 0.6);
}

void main() {
  // Beam warp: how far this scanline band's sample x is displaced. A slow
  // wave across rows plus a per-band variation -- a hair of a pixel scaled
  // by WARP -- so glyphs waver without breaking up.
  float band = floor(gl_FragCoord.y / max(PITCH, 1.0));
  float wob = sin(band * 0.37 + fullSize.y * 0.013) * 0.62
            + sin(band * 1.91 + fullSize.x * 0.007) * 0.38;

  // The waver only pulls pixels that are already lit and green-dominant --
  // text and the lit glyphs. Window borders, chrome and everything dark keep
  // their exact position: long straight HUD lines no longer wobble.
  //
  // Sampling the neighbor instead of the destination keeps each band pulling
  // content consistently (a band's shift is decided by the content of the
  // band it displaces), and since neighboring scanline rows are ~the same
  // color inside a glyph run, the displacement still comes out coherent --
  // while at a border, one bright edge row shifts but the dark rows around
  // it do not, so the line's overall geometry stays put.
  vec2 base = v_texcoord;
  vec2 warpOff = vec2(wob * WARP / fullSize.x, 0.0);
  // Probe half a band up: pulls only where lit green content lives.
  vec3 probeC = texture(tex, base + vec2(0.0, PITCH * 0.5 / fullSize.y)).rgb;
  float probeG = dot(probeC, vec3(0.299, 0.587, 0.114)) * clamp(probeC.g - max(THRESH, 0.2), 0.0, 1.0);
  float pull = smoothstep(0.0, 0.25, probeG);
  vec2 uv = base + warpOff * pull;

  vec3 col = texture(tex, uv).rgb;

  // Per-glyph unevenness. The screen is divided into a grid of glyph-cell
  // sized squares; each cell draws a different phosphor lot number: its halo
  // is a little brighter or dimmer, and its bloom center sits a hair off
  // true. That is what makes the film's glow read as spray rather than
  // stencil -- neighbouring letters never bloom identically. Grain modulates
  // only the ADDED light, never the underlying content.
  vec2 cellId = floor(gl_FragCoord.xy / max(CELL, 4.0));
  float g1 = hash21(cellId);
  float g2 = hash21(cellId + vec2(19.19, 47.47));
  float cellVariance = mix(1.0 - GRAIN * 0.7, 1.0 + GRAIN, g1);
  vec2 haloJitter = (vec2(g1, g2) - 0.5) * GRAIN * CELL * 0.6 / fullSize;

  // Phosphor bloom: a wide kernel, deliberately elongated horizontally
  // (2px per horizontal step against 0.7px vertical) so the glow smears
  // along the scanlines, sampled through the warp so it follows the same
  // band displacement, and nudged by the cell's halo jitter so each glyph's
  // bloom leans a different way.
  //
  // The light budget is what makes the halo actually appear: every kernel
  // sample is gated through srcMask() as an individual light source, and the
  // weights are NORMALIZED. So the accumulated glow is literally "how much
  // phosphor light lives near this pixel" -- it is high on the strokes and
  // decays through the dark pixels beside them, which is exactly where the
  // film's halo lives. The old center-pixel gate zeroed the mask there and
  // the glow never left the glyphs.
  vec2 bUv = uv + haloJitter;
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  for (int k = -3; k <= 3; k++) {
    float w = exp(-float(k * k) / 7.0);
    vec2 o = vec2(float(k) * 2.0, float(k) * 0.7) / fullSize;
    acc += (srcMask(texture(tex, bUv + o).rgb)
          + srcMask(texture(tex, bUv - o).rgb)) * w;
    wsum += 2.0 * w;
  }
  acc /= wsum;
  float halo = acc.g;

  // Only glyph-adjacent pixels glow, and in proportion to nearby light --
  // strokes get a hot core boost, dark pixels beside them carry the halo.
  col += PHOSPHOR * halo * BLOOM * cellVariance;
  col += col * halo * BLOOM * 0.9 * cellVariance;

  fragColor = vec4(col, 1.0);
}`
}