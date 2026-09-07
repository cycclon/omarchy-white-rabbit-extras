import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./settings.js" as Settings
import "./RainModel.js" as RainModel

// Digital-rain screensaver for the White Rabbit theme.
//
// Layering is the whole reason this is a shell plugin rather than a program
// in a terminal. The CRT overlay sits on the Overlay layer and the phosphor
// glow is a Hyprland screen shader, so anything that wants those effects
// applied to it has to render *below* the overlay and *inside* the frame the
// screen shader receives. A layer-shell surface on the Top layer is exactly
// that: above every window, beneath the CRT, and inside the composited frame
// the glow shader operates on. The rain gets scanlines, vignette, bloom and
// beam warp for free, and matches everything else on the desktop.
//
// It runs its own idle clock rather than going through omarchy's screensaver
// hook, because that hook launches a terminal running ttfx and a terminal
// window would land below this surface anyway. While the plugin is active it
// switches the stock screensaver off, and switches it back on when the theme
// changes or the plugin is disabled -- but only if it was the one that
// turned it off.
//
//   omarchy-shell rain status
//   omarchy-shell rain toggle
//   omarchy-shell rain start | stop
//   omarchy-shell rain word "FOLLOW THE WHITE RABBIT"
//   omarchy-shell rain set size 19
//   omarchy-shell rain words
//
// The words themselves are yours to edit: one per line in
// ~/.config/omarchy/branding/rain-words.txt, next to omarchy's own
// screensaver branding. It is watched, so saved changes apply immediately.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"

  // --- theme gate ----------------------------------------------------------

  property bool matrixTheme: false

  // watchChanges only reports that the file moved; re-reading it is the
  // caller's job. Without the reload the gate would latch on whatever theme
  // was active when the shell started.
  FileView {
    id: themeFile
    path: root.stateDir + "/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: themeFile.reload()
    onLoaded: root.matrixTheme = text().trim() === "white-rabbit"
    onLoadFailed: root.matrixTheme = false
  }

  // --- tuning --------------------------------------------------------------

  property bool enabled: true
  property int size: 17          // glyph size in px; drives the whole grid
  property real speed: 1.0       // fall-speed multiplier
  property real wordEvery: 26    // mean seconds between hidden words
  property real glow: 0.10       // bloom around an aligned word (0 = letters only)
  property real reveal: 0.55     // how long the reveal lasts, in seconds
  property real dim: 1.0         // master brightness
  property real vertical: 0.28   // share of words written down a column
  property int idleSeconds: 0    // 0 = follow idle.screensaver in shell.json
  property bool builtins: true   // include the shipped word list

  readonly property int fadeIn: 1400
  readonly property int fadeOut: 240

  FileView {
    id: settingsFile
    path: root.stateDir + "/rain-settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: settingsFile.reload()
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.saveSettings()
  }

  function loadSettings(raw) {
    try {
      var s = JSON.parse(raw)
      if (Settings.num(s.size)) size = Math.round(Settings.clamp(s.size, 8, 48))
      if (Settings.num(s.speed)) speed = Settings.clamp(s.speed, 0.2, 4)
      if (Settings.num(s.wordEvery)) wordEvery = Settings.clamp(s.wordEvery, 4, 600)
      if (Settings.num(s.glow)) glow = Settings.clamp(s.glow, 0, 1)
      if (Settings.num(s.reveal)) reveal = Settings.clamp(s.reveal, 0.1, 4)
      if (Settings.num(s.dim)) dim = Settings.clamp(s.dim, 0.1, 2)
      if (Settings.num(s.vertical)) vertical = Settings.clamp(s.vertical, 0, 1)
      if (Settings.num(s.idleSeconds)) idleSeconds = Math.round(Settings.clamp(s.idleSeconds, 0, 86400))
      if (typeof s.builtins === "boolean") builtins = s.builtins
      if (typeof s.enabled === "boolean") enabled = s.enabled
    } catch (e) {
      console.warn("rain: bad settings json:", e)
    }
  }

  function saveSettings() {
    settingsFile.setText(JSON.stringify({
      enabled: enabled, size: size, speed: speed, wordEvery: wordEvery,
      glow: glow, reveal: reveal, dim: dim, vertical: vertical,
      idleSeconds: idleSeconds, builtins: builtins
    }, null, 2) + "\n")
  }

  function setParam(name, value) {
    var v = Number(value)
    if (!isFinite(v)) return "bad value: " + value
    switch (name) {
      case "size":      size = Math.round(Settings.clamp(v, 8, 48)); break
      case "speed":     speed = Settings.clamp(v, 0.2, 4); break
      case "wordEvery": wordEvery = Settings.clamp(v, 4, 600); break
      case "glow":      glow = Settings.clamp(v, 0, 1); break
      case "reveal":    reveal = Settings.clamp(v, 0.1, 4); break
      case "dim":       dim = Settings.clamp(v, 0.1, 2); break
      case "vertical":  vertical = Settings.clamp(v, 0, 1); break
      case "idle":      idleSeconds = Math.round(Settings.clamp(v, 0, 86400)); break
      case "builtins":  builtins = v !== 0; break
      default:
        return "unknown param: " + name
             + " (size, speed, wordEvery, glow, reveal, dim, vertical, idle,"
             + " builtins)"
    }
    saveSettings()
    if (name === "idle") return "idle = " + idleSeconds
    if (name === "builtins") return "builtins = " + (builtins ? "on" : "off")
    return name + " = " + Settings.fmt(root[name])
  }

  // --- the word list -------------------------------------------------------

  // Kept beside omarchy's own screensaver branding rather than in the plugin
  // or in state, because it is content the user writes, not something the
  // shell owns. Watched, so a save lands on the next alignment.
  readonly property string wordsPath: root.home + "/.config/omarchy/branding/rain-words.txt"
  property var extraWords: []

  FileView {
    id: wordsFile
    path: root.wordsPath
    watchChanges: true
    printErrors: false
    onFileChanged: wordsFile.reload()
    onLoaded: root.parseWords(text())
    onLoadFailed: root.writeWordsTemplate()
  }

  function parseWords(raw) {
    var out = []
    var seen = ({})
    var lines = String(raw).split("\n")

    for (var i = 0; i < lines.length && out.length < 500; i++) {
      var line = lines[i].replace(/^\s+|\s+$/g, "")
      if (!line || line.charAt(0) === "#") continue

      // One glyph per column is the whole mechanic, so a word is folded to the
      // rain's own alphabet: upper case, letters and digits. Apostrophes go
      // (DON'T -> DONT); anything else becomes the space it probably was.
      var w = line.toUpperCase()
                  .replace(/[\u2019']/g, "")
                  .replace(/[^A-Z0-9 ]+/g, " ")
                  .replace(/\s+/g, " ")
                  .replace(/^\s+|\s+$/g, "")

      if (!w || w.length > 48 || seen[w]) continue
      seen[w] = true
      out.push(w)
    }

    root.extraWords = out
  }

  readonly property var wordPool: (builtins ? RainModel.BUILTIN_WORDS : [])
                                  .concat(extraWords)

  function writeWordsTemplate() {
    wordsFile.setText(
      "# Words and phrases hidden in the digital rain.\n"
    + "#\n"
    + "# One per line. Blank lines and lines starting with # are ignored.\n"
    + "# Everything is upper-cased and folded to letters, digits and spaces,\n"
    + "# so LINUX, \"Free your mind\" and 1999 all work.\n"
    + "#\n"
    + "# These are added to the list the plugin ships with. To use only what is\n"
    + "# in this file:  omarchy-shell rain set builtins 0\n"
    + "#\n"
    + "# Spaces are worth using. The columns under a space keep raining as\n"
    + "# normal, so a phrase never reads as a solid block of synchronised\n"
    + "# drops -- which is most of what keeps a long one hard to spot.\n"
    + "#\n"
    + "# Saved changes apply immediately. See them all with:\n"
    + "#   omarchy-shell rain words\n")
  }

  // --- idle ----------------------------------------------------------------

  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle
                                    ? shell.shellConfig.idle : ({})
  readonly property int shellScreensaverSeconds: {
    var n = Number(idleConfig.screensaver)
    return isFinite(n) && n > 0 ? Math.round(n) : 150
  }
  readonly property int timeoutSeconds: idleSeconds > 0 ? idleSeconds : shellScreensaverSeconds

  readonly property bool active: matrixTheme && enabled
  property bool stayAwake: false
  property bool showing: false
  property bool mounted: false
  property bool primed: false
  property real shownAt: 0

  IdleMonitor {
    id: idle
    enabled: root.active && !root.stayAwake
    timeout: root.timeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: isIdle ? root.start("idle") : root.dismiss("activity")
  }

  function start(reason) {
    if (!root.active || root.showing) return
    root.primed = true
    root.mounted = true
    root.showing = true
    root.shownAt = Date.now()
    unmountTimer.stop()
    cursorProcess.run(true)
  }

  function dismiss(reason) {
    if (!root.showing) return
    // Mapping a fullscreen surface under a stationary pointer produces a
    // hover event, which would otherwise dismiss the screensaver in the same
    // frame it appeared. Real movement still arrives via the idle monitor.
    if (reason === "pointer" && Date.now() - root.shownAt < 800) return
    root.showing = false
    unmountTimer.restart()
    cursorProcess.run(false)
  }

  onActiveChanged: {
    if (!active) dismiss("inactive")
    screensaverToggle.apply(active)
  }
  Component.onDestruction: screensaverToggle.apply(false)

  // The fade-out used to drop the whole surface after the animation; now the
  // window stays mapped (see the note at the surface), so this timer only
  // marks the rain fully hidden. It still stops the scene's frame clock via
  // pane visibility, so nothing renders while idle.
  Timer {
    id: unmountTimer
    interval: root.fadeOut + 80
    onTriggered: root.mounted = false
  }

  Process {
    id: cursorProcess
    function run(hide) {
      if (running) return
      var v = hide ? "true" : "false"
      command = ["bash", "-lc",
        "hyprctl eval 'hl.config({ cursor = { invisible = " + v + " } })' >/dev/null 2>&1 || "
        + "hyprctl keyword cursor:invisible " + v + " >/dev/null 2>&1 || true"]
      running = true
    }
  }

  // omarchy's own screensaver would otherwise start a terminal running ttfx
  // underneath this surface: invisible, but burning a core. The marker file
  // records that the switch was ours, so a user who turned the screensaver
  // off themselves still finds it off when they leave the White Rabbit theme.
  Process {
    id: screensaverToggle
    function apply(off) {
      if (running) { pending = off; hasPending = true; return }
      command = ["bash", "-lc",
        'TOG="$HOME/.local/state/omarchy/toggles/screensaver-off"; '
        + 'MARK="$HOME/.local/state/omarchy/rain-owns-screensaver-off"; '
        + (off
           ? 'mkdir -p "$(dirname "$TOG")"; [[ -f $TOG ]] || { touch "$TOG" "$MARK"; }'
           : '[[ -f $MARK ]] && rm -f "$TOG" "$MARK"; true')]
      running = true
    }
    property bool hasPending: false
    property bool pending: false
    onExited: {
      if (!hasPending) return
      hasPending = false
      apply(pending)
    }
  }

  // Stay-awake is a flag file, and a file that does not exist cannot be
  // watched, so the directory is watched and the flag re-probed.
  Process {
    id: stayAwakeProbe
    command: ["bash", "-c",
      'mkdir -p "$HOME/.local/state/omarchy/indicators"; '
      + '[[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && echo yes || echo no']
    stdout: SplitParser {
      onRead: function (line) { root.stayAwake = String(line).trim() === "yes" }
    }
    onExited: stayAwakeWatcher.reload()
  }

  FileView {
    id: stayAwakeWatcher
    path: root.stateDir + "/indicators"
    watchChanges: true
    printErrors: false
    onFileChanged: if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  Component.onCompleted: {
    stayAwakeProbe.running = true
    screensaverToggle.apply(root.active)
  }

  // --- IPC -----------------------------------------------------------------

  function eachScene(fn) {
    var out = ""
    for (var i = 0; i < surfaces.instances.length; i++) {
      var scene = surfaces.instances[i].scene
      if (!scene) continue
      var r = fn(scene)
      if (!out) out = r
    }
    return out
  }

  IpcHandler {
    target: "rain"

    function status(): string {
      if (!root.matrixTheme) return "inactive (theme is not White Rabbit)"
      if (!root.enabled) return "off"
      return (root.showing ? "showing" : "armed")
        + " -- idle " + root.timeoutSeconds + "s"
        + ", size " + root.size
        + ", speed " + Settings.fmt(root.speed)
        + ", word every " + Settings.fmt(root.wordEvery) + "s"
        + ", glow " + Settings.fmt(root.glow)
        + ", vertical " + Settings.fmt(root.vertical)
        + (root.stayAwake ? " (stay-awake held)" : "")
    }

    function toggle(): string {
      root.enabled = !root.enabled
      root.saveSettings()
      return root.enabled ? "digital rain armed" : "digital rain off"
    }

    function start(): string {
      if (!root.active) return "inactive"
      root.start("ipc")
      return "showing"
    }

    function stop(): string {
      root.dismiss("ipc")
      return "dismissed"
    }

    function word(text: string): string {
      var down = Math.random() < root.vertical
      var out = root.eachScene(function (scene) { return scene.forceWord(text, down) })
      return out || "rain is not running -- try `omarchy-shell rain start` first"
    }

    function words(): string {
      var stock = root.builtins ? RainModel.BUILTIN_WORDS.length : 0
      return root.wordPool.length + " words (" + stock + " built in, "
           + root.extraWords.length + " yours)\n"
           + root.wordPool.join(", ")
           + "\n\nedit " + root.wordsPath
           + (root.builtins ? "" : "\nbuilt-in words are off: rain set builtins 1")
    }

    function set(name: string, value: string): string {
      return root.setParam(name, value)
    }

    function reset(): string {
      size = 17; speed = 1.0; wordEvery = 26; glow = 0.10
      reveal = 0.55; dim = 1.0; vertical = 0.28; idleSeconds = 0; builtins = true
      root.saveSettings()
      return "rain settings reset to defaults"
    }
  }

  // --- the surface ---------------------------------------------------------

  Variants {
    id: surfaces
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      readonly property alias scene: sceneLoader.item

      screen: modelData
      // Keep the window mapped once primed and fade content instead of
      // toggling visibility: remapping the surface destroys and rebuilds the
      // scene graph, and the layer textures the shader samples come back
      // empty on the second mount -- every run after the first rendered
      // black, with only the word-glow bloom flashing through.
      visible: root.active && root.primed
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omarchy-rain"
      // Top, not Overlay: this has to cover every window while still passing
      // under omarchy-crt. See the note at the top of the file.
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive
                                                : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Input is swallowed only while the rain is up, so the keystroke that
      // dismisses it does not also land in whatever was underneath. During
      // the fade-out the surface is already transparent to input.
      property Region passthrough: Region {}
      mask: root.showing ? null : panel.passthrough

      Item {
        id: pane
        anchors.fill: parent
        opacity: root.showing ? 1 : 0
        enabled: root.showing
        // Frame clock runs only while the rain is up: running: pane.visible
        // on the scene, and visible follows `mounted`, which drops 320ms
        // after the fade-out finishes.
        visible: root.mounted

        Behavior on opacity {
          NumberAnimation {
            duration: root.showing ? root.fadeIn : root.fadeOut
            easing.type: Easing.InOutQuad
          }
        }

        Rectangle { anchors.fill: parent; color: "#010604" }

        Loader {
          id: sceneLoader
          anchors.fill: parent
          // Built on the first screensaver rather than at shell start: 200
          // columns of text is not a cost to pay during login for something
          // that may not be wanted for another two minutes.
          active: root.primed
          sourceComponent: sceneComponent
        }

        Component {
          id: sceneComponent
          RainScene {
            running: root.showing
            fontSize: root.size
            speedScale: root.speed
            wordEvery: root.wordEvery
            halo: root.glow
            glowSigma: root.reveal
            dim: root.dim
            verticalChance: root.vertical
            extraWords: root.extraWords
            useBuiltins: root.builtins
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.showing
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPositionChanged: function (mouse) { root.dismiss("pointer") }
        onPressed: function (mouse) { root.dismiss("click") }
        onWheel: function (wheel) { root.dismiss("wheel") }
      }

      Item {
        anchors.fill: parent
        focus: root.showing
        Keys.onPressed: function (event) { root.dismiss("key") }
      }
    }
  }
}
