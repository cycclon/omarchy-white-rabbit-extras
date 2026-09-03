import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./settings.js" as Settings

// CRT tube overlay for the White Rabbit theme.
//
// The film's look comes from the tube, not the font: thin horizontal lines
// cutting through every glyph, a soft phosphor haze, darker edges. Those are
// display properties, so they are painted one step above every window -- a
// transparent layer-shell surface on the Overlay layer, one per screen,
// driven by a shader.
//
// A normal alpha-blended overlay darkens by painting translucent black,
// which is exactly what this shader does:
//
//   scanlines  -- a translucent black band every `pitch` rows, soft-edged so
//                 it reads as a video signal rather than a hard grid
//   vignette   -- radial darkening toward the tube's edges
//   haze       -- a faint green floor that breathes slowly, so "black" never
//                 reads as OLED black
//   strength   -- master translucency: scales every layer at once
//
// The surface never takes input and never reserves space: keyboardFocus
// None, exclusionMode Ignore, and an empty Region mask routes every click
// through to whatever is underneath.
//
// Active only while the theme is White Rabbit (theme.name in the state dir is
// watched, so the overlay drops itself the moment the theme changes) and
// toggleable/tunable at runtime over IPC:
//
//   omarchy-shell crt status
//   omarchy-shell crt toggle
//   omarchy-shell crt set strength 0.7
//   omarchy-shell crt set pitch 4
//   omarchy-shell crt set scan 0.5
//   omarchy-shell crt set vignette 0.4
//   omarchy-shell crt set haze 0.05
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

  // Settings live in a small file so tweaks survive shell restarts.
  // Defaults: pitch 3 (the film's line spacing), scan 0.40 band darkness,
  // vignette 0.36, haze 0.030 green floor, strength 1.0 master scale.
  property real pitch: 3          // rows between lines (2 = fine, 4 = chunky)
  property real scan: 0.40        // scanline band darkness (0 = off)
  property real vignette: 0.36    // corner darkening (0 = off)
  property real haze: 0.030       // green floor in the blacks (0 = off)
  property real strength: 1.0     // master translucency (0.5 = subtle, 2 = heavy)
  property bool enabled: true

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/crt-settings.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.saveSettings()
  }

  function loadSettings(raw) {
    try {
      var s = JSON.parse(raw)
      if (Settings.num(s.pitch)) pitch = Settings.clamp(s.pitch, 2, 8)
      if (Settings.num(s.scan)) scan = Settings.clamp(s.scan, 0, 1)
      if (Settings.num(s.vignette)) vignette = Settings.clamp(s.vignette, 0, 1)
      if (Settings.num(s.haze)) haze = Settings.clamp(s.haze, 0, 0.2)
      if (Settings.num(s.strength)) strength = Settings.clamp(s.strength, 0, 2)
      if (typeof s.enabled === "boolean") enabled = s.enabled
    } catch (e) {
      console.warn("crt: bad settings json:", e)
    }
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({
      pitch: pitch, scan: scan, vignette: vignette,
      haze: haze, strength: strength, enabled: enabled
    }, null, 2) + "\n")
  }

  function setParam(name, value) {
    var v = Number(value)
    if (!isFinite(v)) return "bad value: " + value
    switch (name) {
      case "pitch":    pitch = Settings.clamp(v, 2, 8); break
      case "scan":     scan = Settings.clamp(v, 0, 1); break
      case "vignette": vignette = Settings.clamp(v, 0, 1); break
      case "haze":     haze = Settings.clamp(v, 0, 0.2); break
      case "strength": strength = Settings.clamp(v, 0, 2); break
      default: return "unknown param: " + name + " (pitch, scan, vignette, haze, strength)"
    }
    saveSettings()
    return name + " = " + Settings.fmt(root[name])
  }

  // --- IPC -----------------------------------------------------------------

  IpcHandler {
    target: "crt"

    function toggle(): string {
      // Must qualify: IpcHandler has its own `enabled` property — an
      // unqualified assignment here flips the handler itself off and
      // deregisters the whole IPC target.
      root.enabled = !root.enabled
      saveSettings()
      return root.enabled ? "crt overlay on" : "crt overlay off"
    }

    function status(): string {
      if (!matrixTheme) return "inactive (theme is not White Rabbit)"
      return root.enabled
        ? "on -- pitch " + fmt(pitch) + ", scan " + fmt(scan)
          + ", vignette " + fmt(vignette) + ", haze " + fmt(haze)
          + ", strength " + fmt(strength)
        : "off"
    }

    function set(name: string, value: string): string {
      return setParam(name, value)
    }

    function reset(): string {
      pitch = 3; scan = 0.40; vignette = 0.36; haze = 0.030; strength = 1.0
      saveSettings()
      return "crt settings reset to defaults"
    }
  }

  // Number formatting for the status line: trim trailing zeros.
  function fmt(n) {
    return String(Math.round(n * 1000) / 1000)
  }

  // --- the tube ------------------------------------------------------------

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: root.matrixTheme && root.enabled
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omarchy-crt"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region { }

      ShaderEffect {
        anchors.fill: parent
        blending: true

        readonly property vector2d resolution: Qt.vector2d(width, height)
        readonly property real pitch: root.pitch
        readonly property real scan: root.scan
        readonly property real vignette: root.vignette
        readonly property real haze: root.haze
        readonly property real strength: root.strength
        property real time: 0

        // Slow phosphor breathe: 8s period.
        NumberAnimation on time {
          from: 0; to: Math.PI * 2
          duration: 8000
          loops: Animation.Infinite
        }

        vertexShader: "shaders/crt.vert.qsb"
        fragmentShader: "shaders/crt.frag.qsb"
      }
    }
  }
}