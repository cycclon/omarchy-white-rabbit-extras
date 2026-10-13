import QtQuick
import QtQuick.Shapes

// The menu card's frame, in the language of the hud-borders Hyprland plugin
// (the theme's window decoration) without copying it: the same thin outer
// hairline and thicker inner line, but its own outline. The right edge steps
// inward partway down and never comes back, so the card is uneven in shape,
// and a small gauge sits in the top-left instead of the bottom-right.
//
// Geometry mirrors FrameArt.cpp: the outline runs along the edge of the item,
// each ring is that outline offset inward with mitred joins, so the two lines
// stay parallel around cuts and the step alike.
Item {
  id: root

  // Inner-line colour (the accent), also used for the gauge.
  property color color: "#45abbf"
  // Outer hairline colour (dimmer).
  property color outerColor: "#0b86b3"
  // Card fill, clipped to the outline so cuts and the step show the scrim.
  property color fillColor: "transparent"
  // Phosphor wash over the fill in the line colour, 0..1. Driven by the
  // menu's power-on/off animation.
  property real glow: 0

  property int outerThickness: 1
  property int gap: 3
  property int innerThickness: 2

  // Corner cut depths, in px.
  property int chamferTL: 0
  property int chamferTR: 24
  property int chamferBR: 14
  property int chamferBL: 14

  // Right-edge step: at `stepStart` (a fraction of the height) the edge moves
  // inward by `stepDepth` at 45 degrees and stays there down to the bottom.
  property real stepStart: 0.4
  property int stepDepth: 16

  // Gauge on the inside of the top line, butted against the left line: a bar
  // with a square left end, then slashes, all leaning like the top-right cut.
  property bool gauge: true
  property int gaugeHeight: 7
  property int gaugeLength: 44
  property int gaugeInset: 2
  property int gaugeStripes: 3
  property int gaugeStripeWidth: 6
  property int gaugeGap: 3

  // Thickness of the whole frame; content should sit at least this far in.
  readonly property real _d: root.outerThickness + root.gap + root.innerThickness
  // Extra room content needs on the right, since the step narrows the card.
  readonly property real rightIndent: root.stepDepth

  readonly property var outline: root.framePolygon(width, height)

  function framePolygon(W, H) {
    if (W <= 0 || H <= 0) return []
    var lim = Math.min(W, H) / 2
    var clamp = function(v) { return Math.max(0, Math.min(v, lim)) }
    var tl = clamp(root.chamferTL), tr = clamp(root.chamferTR)
    var bl = clamp(root.chamferBL)
    var d = Math.max(0, Math.min(root.stepDepth, W / 4))
    var br = Math.max(0, Math.min(root.chamferBR, (W - d) / 2, H / 2))
    // The step's slope needs to land above the bottom-right cut.
    var y0 = Math.max(H * root.stepStart, tr)
    if (y0 + d > H - br) d = 0

    var pts = [[tl, 0], [W - tr, 0], [W, tr]]
    if (d > 0) pts.push([W, y0], [W - d, y0 + d])
    pts.push([W - d, H - br], [W - d - br, H], [bl, H], [0, H - bl], [0, tl])

    // A zero cut leaves two vertices on one spot and a straight run leaves
    // collinear ones; both would give the offset a degenerate edge.
    var out = []
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i], q = out[out.length - 1]
      if (!q || Math.hypot(p[0] - q[0], p[1] - q[1]) > 1e-6) out.push(p)
    }
    while (out.length > 1 && Math.hypot(out[0][0] - out[out.length - 1][0], out[0][1] - out[out.length - 1][1]) < 1e-6)
      out.pop()

    var clean = []
    for (var j = 0; j < out.length; j++) {
      var a = out[(j + out.length - 1) % out.length], b = out[j], c = out[(j + 1) % out.length]
      if (Math.abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) > 1e-9) clean.push(b)
    }
    return clean
  }

  // Moves every edge `s` inward and re-joins them at mitred vertices.
  function offsetPolygon(pts, s) {
    var n = pts.length
    var normals = []
    for (var i = 0; i < n; i++) {
      var a = pts[i], b = pts[(i + 1) % n]
      var len = Math.hypot(b[0] - a[0], b[1] - a[1])
      // Clockwise in y-down coordinates: the inward normal is (-dy, dx).
      normals.push([-(b[1] - a[1]) / len, (b[0] - a[0]) / len])
    }
    var out = []
    for (var j = 0; j < n; j++) {
      var n1 = normals[(j + n - 1) % n], n2 = normals[j]
      var k = s / (1 + n1[0] * n2[0] + n1[1] * n2[1])
      out.push([pts[j][0] + (n1[0] + n2[0]) * k, pts[j][1] + (n1[1] + n2[1]) * k])
    }
    return out
  }

  function toPoints(pts) {
    return pts.map(function(p) { return Qt.point(p[0], p[1]) })
  }

  // A stroked ring: repeat the first two vertices so the start gets a mitre
  // like every other corner (PathClose is not available in this build).
  function ring(s) {
    if (root.outline.length < 3) return []
    var pts = root.offsetPolygon(root.outline, s)
    return root.toPoints(pts.concat([pts[0], pts[1]]))
  }

  function gaugeShapes(W, H) {
    if (!root.gauge || root.gaugeHeight <= 0 || root.gaugeLength <= 0) return []
    var h = root.gaugeHeight
    // The same air off the top line and off the left one.
    var top = root._d + root.gaugeInset
    var x0 = root._d + root.gaugeInset
    var end = x0 + root.gaugeLength + root.gaugeStripes * (root.gaugeGap + root.gaugeStripeWidth) + h
    if (end > W - root.chamferTR - root._d || top + h > H - root._d) return []

    // Leaning like the top-right cut: dropping h moves right by h.
    var slant = function(x, w) {
      return [Qt.point(x, top), Qt.point(x + w, top), Qt.point(x + w + h, top + h), Qt.point(x + h, top + h), Qt.point(x, top)]
    }
    // The main bar's left end is square, so it sits flush with the left line.
    var L = root.gaugeLength
    var shapes = [[Qt.point(x0, top), Qt.point(x0 + L, top), Qt.point(x0 + L + h, top + h), Qt.point(x0, top + h), Qt.point(x0, top)]]
    for (var i = 0; i < root.gaugeStripes; i++)
      shapes.push(slant(x0 + L + root.gaugeGap + i * (root.gaugeStripeWidth + root.gaugeGap), root.gaugeStripeWidth))
    return shapes
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    asynchronous: false

    // Card fill, following the outline.
    ShapePath {
      fillColor: root.fillColor
      strokeColor: "transparent"
      strokeWidth: 0
      PathPolyline { path: root.outline.length >= 3 ? root.toPoints(root.outline.concat([root.outline[0]])) : [] }
    }

    // Phosphor wash.
    ShapePath {
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.glow)
      strokeColor: "transparent"
      strokeWidth: 0
      PathPolyline { path: root.glow > 0 && root.outline.length >= 3 ? root.toPoints(root.outline.concat([root.outline[0]])) : [] }
    }

    // Outer hairline.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.outerThickness > 0 ? root.outerColor : "transparent"
      strokeWidth: root.outerThickness
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      PathPolyline { path: root.ring(root.outerThickness / 2) }
    }

    // Inner line.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.innerThickness > 0 ? root.color : "transparent"
      strokeWidth: root.innerThickness
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      PathPolyline { path: root.ring(root.outerThickness + root.gap + root.innerThickness / 2) }
    }

    // Gauge.
    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      strokeWidth: 0
      PathMultiline { paths: root.gaugeShapes(root.width, root.height) }
    }
  }
}
