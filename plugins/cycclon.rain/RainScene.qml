import QtQuick
import "./RainModel.js" as RainModel

// One screen's worth of rain.
//
// Split out from the plugin entry point so it can be run on its own in a
// plain window while it is being tuned -- everything here is ordinary
// QtQuick, with no layer-shell or shell-plugin dependency.
//
// The renderer is deliberately lopsided: Qt draws the glyphs, once, into an
// offscreen layer, and a shader does all the animating by sliding a window of
// brightness down each column. That means a 2560x1440 field of ~17000 glyphs
// costs one text layout per column per drop instead of per frame.
Item {
  id: scene

  // --- tuning --------------------------------------------------------------

  property bool running: true
  property string fontFamily: "Noto Sans CJK JP"
  property int fontSize: 17
  property real speedScale: 1.0
  property real wordEvery: 26      // seconds between hidden words
  property real glowSigma: 0.5     // half-width of the reveal, in seconds
  property real halo: 0.10         // bloom around an aligned word
  property real dim: 1.0           // master brightness
  property real verticalChance: 0.28
  property var extraWords: []      // the user's own list
  property bool useBuiltins: true

  readonly property var words: (useBuiltins ? RainModel.BUILTIN_WORDS : []).concat(extraWords)

  property color headColor: "#d8ffe4"
  property color bodyColor: "#2fd45c"
  property color glowColor: "#eafff1"

  readonly property int cellW: Math.max(6, Math.round(fontSize * 0.78))
  readonly property int cellH: Math.max(8, Math.round(fontSize * 1.18))
  readonly property int cols: Math.max(8, Math.ceil(width / cellW))
  readonly property int rows: Math.max(8, Math.ceil(height / cellH))

  // Head positions are encoded into two bytes spanning this many rows, which
  // has to cover a drop from just above the top to trail-length past the
  // bottom. `headBias` is the slack above row zero.
  readonly property real headBias: 4
  readonly property real headScale: rows * 2 + 8

  readonly property var cfg: ({
    speedMin: 6.0,
    speedMax: 20.0,
    speedScale: scene.speedScale,
    trailMin: 0.14,
    trailMax: 0.55,
    brightMin: 0.45,
    gapMin: 0.15,
    gapMax: 3.2,
    startSpread: 4.0,
    mutationsPerSecond: 14,
    wordEvery: scene.wordEvery,
    glowSigma: scene.glowSigma,
    verticalChance: scene.verticalChance,
    // cfg is handed to the field every frame, so editing the word file takes
    // effect on the next alignment without rebuilding anything.
    words: scene.words
  })

  // The rain is driven by the display's frame clock, which on a 170 Hz panel
  // is far more often than falling text needs. Coalescing to this rate keeps
  // the motion smooth -- a fast column moves four pixels a step -- and cuts
  // the per-frame work, and its power draw, by most of a factor of three.
  readonly property real minStep: 1 / 60
  property real pending: 0

  property var field: null
  property int dbg: 0
  property var textItems: []
  property var headItems: []
  property var stateItems: []

  onColsChanged: rebuild()
  onRowsChanged: rebuild()
  onWidthChanged: rebuild()
  onHeightChanged: rebuild()
  Component.onCompleted: rebuild()

  function rebuild() {
    // Anchors resolve after creation, and size and grid both signal, so this
    // runs several times for one real change. Building a field for a
    // zero-sized item, or rebuilding one that already has the right grid,
    // throws away a pre-roll for nothing.
    if (width < 32 || height < 32) return
    if (field && field.cols === cols && field.rows === rows) return
    field = RainModel.createField(cols, rows, cfg)
    // Long enough for the slowest column to have crossed the screen once.
    RainModel.preroll(field, rows / (cfg.speedMin * cfg.speedScale)
                             + cfg.gapMax + cfg.startSpread)
    textItems = []
    headItems = []
    stateItems = []
  }

  // The Repeaters are populated asynchronously, so the caches are filled the
  // first frame every delegate exists rather than in onCompleted.
  function cacheItems() {
    if (textItems.length === cols && headItems.length === cols
        && stateItems.length === cols) return false

    var t = [], h = [], s = []
    for (var i = 0; i < cols; i++) {
      var ti = glyphRepeater.itemAt(i)
      var hi = headRepeater.itemAt(i)
      var si = stateRepeater.itemAt(i)
      if (!ti || !hi || !si) return true
      t.push(ti); h.push(hi); s.push(si)
    }
    textItems = t; headItems = h; stateItems = s
    return false
  }

  function encodeHead(head) {
    var v = (head + headBias) / headScale
    var q = Math.max(0, Math.min(65535, Math.round(v * 65535)))
    return { hi: (q >> 8) / 255, lo: (q & 255) / 255 }
  }

  function tick(dt) {
    if (!field) return

    pending += dt
    if (pending < minStep) return
    var step = Math.min(pending, 0.1)
    pending = 0

    field.cfg = cfg
    RainModel.advance(field, step)
    if (cacheItems()) return

    for (var c = 0; c < cols; c++) {
      var col = field.columns[c]

      if (col.dirty) {
        textItems[c].text = col.glyphs.join("\n")
        col.dirty = false
      }

      var e = encodeHead(col.active ? col.head : -1000)
      // Alpha is pinned to 1 on both texels: this layer is captured through
      // layer.enabled, which composites it with premultiplied alpha. Any
      // alpha below 1 scales r/g/b down with it, so an encoded value (head
      // position, trail, brightness) can only ride in a channel whose texel
      // alpha is exactly 1 -- otherwise it comes back corrupted by whatever
      // brightness happened to be that frame.
      headItems[c].color = Qt.rgba(e.hi, e.lo, Math.min(col.trail, 255) / 255, 1)
      stateItems[c].color = Qt.rgba(col.bright, 0, 0, 1)
    }

    var w = field.word
    effect.wordRect = w ? Qt.vector4d(w.col0, w.col1, w.row0, w.row1)
                        : Qt.vector4d(-9, -9, -9, -9)
    effect.wordGlow = RainModel.glowAt(field)
    if (dbg) { console.warn("rain: ticking normally after", dbg, "stalled frames"); dbg = 0 }
  }

  function forceWord(text, vertical) {
    if (!field) return "rain is not running"
    return RainModel.forceWord(field, text, vertical)
  }

  function glowNow() {
    return field ? RainModel.glowAt(field) : 0
  }

  function currentWord() {
    if (!field || !field.word) return ""
    return field.word.text
  }

  FrameAnimation {
    running: scene.running && scene.field !== null
    onTriggered: scene.tick(frameTime)
  }

  // --- the glyph field -----------------------------------------------------

  // Rendered on screen, at the scene's own position, so the batch renderer
  // never has grounds to cull it as off-viewport -- that culling is what
  // blanked every run after the first when this content used to be parked
  // off to the side (the layer texture came back stale/empty on remount, and
  // only the word-glow bloom still flashed through). Direct compositing of
  // this item is switched off with `hideSource` on the ShaderEffectSource
  // below, not by z-order or position: a transparent pixel in the shader
  // output does not hide whatever sits behind it at that same spot, so an
  // on-screen source with no hideSource showed through as a full grid of raw
  // white glyphs wherever the rain shader had nothing lit.
  Item {
    id: glyphContent
    x: 0
    y: 0
    width: scene.width
    height: scene.height

    Repeater {
      id: glyphRepeater
      model: scene.cols

      Text {
        required property int index
        x: index * scene.cellW
        y: 0
        width: scene.cellW
        color: "white"
        font.family: scene.fontFamily
        font.pixelSize: scene.fontSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        lineHeight: scene.cellH
        lineHeightMode: Text.FixedHeight
        wrapMode: Text.NoWrap
        textFormat: Text.PlainText
      }
    }
  }

  ShaderEffectSource {
    id: glyphLayer
    sourceItem: glyphContent
    hideSource: true
    smooth: true
  }

  // Per-column state, two texels each laid out side by side: head hi/lo and
  // trail in the first (r,g,b), brightness in the second (r). One row, so
  // the sampler can never blend this texel with a neighbouring row the way a
  // cols-by-2 texture could -- that vertical blend was what turned every
  // cell lit in the mapped-panel context. Two texels per column rather than
  // one is what keeps brightness off the alpha channel: alpha has to stay at
  // 1 everywhere in this layer (see tick()), so brightness needs a texel of
  // its own instead of riding in the first one's `a`. Rewritten every frame;
  // at 2560 wide that is a 400x1 texture, still cheaper to hand the GPU than
  // any of the ways of saying the same thing in uniforms.
  //
  // Kept on screen and hidden via hideSource for the same reason as
  // glyphContent above, rather than parked off to the side.
  Item {
    id: dataContent
    x: 0
    y: 0
    width: scene.cols * 2
    height: 1

    Repeater {
      id: headRepeater
      model: scene.cols
      Rectangle {
        required property int index
        x: index * 2; y: 0; width: 1; height: 1
        antialiasing: false
        color: "black"
      }
    }

    Repeater {
      id: stateRepeater
      model: scene.cols
      Rectangle {
        required property int index
        x: index * 2 + 1; y: 0; width: 1; height: 1
        antialiasing: false
        color: "black"
      }
    }
  }

  ShaderEffectSource {
    id: dataLayer
    sourceItem: dataContent
    hideSource: true
    smooth: false
  }

  ShaderEffect {
    id: effect
    anchors.fill: parent
    blending: true

    readonly property var glyphSource: glyphLayer
    readonly property var dataSource: dataLayer

    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property vector2d cell: Qt.vector2d(scene.cellW, scene.cellH)
    readonly property vector2d grid: Qt.vector2d(scene.cols, scene.rows)
    readonly property color headColor: scene.headColor
    readonly property color bodyColor: scene.bodyColor
    readonly property color glowColor: scene.glowColor
    readonly property real headScale: scene.headScale
    readonly property real headBias: scene.headBias
    readonly property real trailGamma: 1.7
    readonly property real headLen: 1.8
    readonly property real halo: scene.halo
    readonly property real dim: scene.dim

    property vector4d wordRect: Qt.vector4d(-9, -9, -9, -9)
    property real wordGlow: 0

    fragmentShader: Qt.resolvedUrl("shaders/rain.frag.qsb")
  }
}
