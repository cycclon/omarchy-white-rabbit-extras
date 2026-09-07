#version 440

// Digital rain compositor.
//
// The glyphs themselves are drawn by Qt into `glyphSource` -- one Text item
// per column, white, static for the life of a drop. Nothing in that layer
// moves, so it only re-renders when a column recycles or a glyph mutates.
//
// All the motion lives here. `dataSource` is a (cols*2) x 1 texture, two
// texels per rain column, rewritten every frame:
//
//   texel 0: r,g = head position, 16-bit over [-headBias, headScale-headBias]
//            b   = trail length in rows
//   texel 1: r   = column brightness
//
// Alpha is 1 in both texels. This layer is captured through layer.enabled,
// which composites with premultiplied alpha, so anything riding in a texel's
// own alpha channel would come back scaled by that same alpha -- brightness
// gets its own texel instead of sharing one with the head/trail encoding.
//
// A pixel is lit when its cell sits between the head and the tail of its
// column's drop. That is the whole effect: a moving window of brightness
// slid down a static field of glyphs.
//
// The hidden words ride on top. A word is a rectangle of cells -- one row of
// several columns for a horizontal word, one column of several rows for a
// vertical one -- whose letters were written into the glyph layer when the
// drop was scheduled. `wordGlow` peaks at the instant the participating
// columns' heads line up on that rectangle, lifting those cells toward the
// glow colour and adding a soft halo around them. The rest of the time it is
// zero and the letters are indistinguishable from rain.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 resolution;
  vec2 cell;        // cell width, cell height in px
  vec2 grid;        // columns, rows
  vec4 headColor;
  vec4 bodyColor;
  vec4 glowColor;
  vec4 wordRect;    // col0, col1, row0, row1
  float headScale;  // head encoding span, in rows
  float headBias;   // head encoding offset, in rows
  float trailGamma; // trail falloff exponent
  float headLen;    // rows over which the head fades into the body colour
  float wordGlow;   // 0 at rest, 1 at the moment of alignment
  float halo;       // halo strength multiplier
  float dim;        // master brightness
};

layout(binding = 1) uniform sampler2D glyphSource;
layout(binding = 2) uniform sampler2D dataSource;

void main() {
  vec2 fc = qt_TexCoord0 * resolution;
  float col = floor(fc.x / cell.x);
  float row = floor(fc.y / cell.y);

  // Two texels per column, side by side in one row: v is irrelevant with
  // nearest sampling, but 0.5 is the safe center.
  float u0 = (col * 2.0 + 0.5) / (grid.x * 2.0);
  float u1 = (col * 2.0 + 1.5) / (grid.x * 2.0);
  vec4 d0 = texture(dataSource, vec2(u0, 0.5));
  vec4 d1 = texture(dataSource, vec2(u1, 0.5));

  float head = (d0.r * 65280.0 + d0.g * 255.0) / 65535.0 * headScale - headBias;
  float trail = d0.b * 255.0;
  float bright = d1.r;

  // Distance behind the head, in rows. Negative means the drop has not
  // reached this cell yet; beyond `trail` it has already gone dark.
  //
  // The leading edge is a ramp rather than a step, and not only because a
  // hard edge pops. Aligned columns arrive at the word row at the same
  // instant but integrate their positions independently, so at the moment of
  // alignment a head can sit a ten-thousandth of a row short of it. Against a
  // step that letter is simply missing from the word; against a ramp it is
  // indistinguishable from its neighbours.
  float dist = head - row;
  float lit = smoothstep(-1.0, 0.0, dist) * step(dist, trail) * step(0.5, trail);

  float fall = pow(clamp(1.0 - dist / max(trail, 1.0), 0.0, 1.0), trailGamma);
  float headness = 1.0 - smoothstep(0.0, headLen, dist);

  // The word rectangle, and how much of the glow it is currently getting.
  float inWord =
      step(wordRect.x - 0.5, col) * step(col, wordRect.y + 0.5) *
      step(wordRect.z - 0.5, row) * step(row, wordRect.w + 0.5);
  float w = inWord * wordGlow;

  // Columns cross the word row at their own speeds, so a frame either side
  // of the alignment leaves some letters a row further into their trail than
  // others -- readable, but a ragged mix of white and green. Holding word
  // cells at head colour for the length of the reveal is what makes the word
  // arrive as one thing instead of five.
  vec3 tint = mix(bodyColor.rgb, headColor.rgb, max(headness, w));
  tint = mix(tint, glowColor.rgb, clamp(w * 0.25, 0.0, 1.0));

  float amp = fall * bright * lit * dim * (1.0 + w * 0.4);
  float cover = texture(glyphSource, qt_TexCoord0).a;

  // Light that does not come from a glyph. The letters are already at the
  // heads of their columns and so already the brightest things around; this
  // only has to tip the eye off, so it is a soft capsule around the word
  // rather than anything with an edge. Anything harder reads as a spotlight
  // and gives the whole trick away at a glance.
  vec2 mid = vec2((wordRect.x + wordRect.y + 1.0) * 0.5 * cell.x,
                  (wordRect.z + wordRect.w + 1.0) * 0.5 * cell.y);
  vec2 halfSize = vec2((wordRect.y - wordRect.x + 1.0) * 0.5 * cell.x,
                   (wordRect.w - wordRect.z + 1.0) * 0.5 * cell.y);
  vec2 sigma = vec2(cell.x * 2.0, cell.y * 1.1);
  vec2 dxy = max(abs(fc - mid) - halfSize * vec2(0.72, 0.30), vec2(0.0));
  float bloom = exp(-dot(dxy / sigma, dxy / sigma)) * wordGlow * halo * dim;

  fragColor = vec4(tint * cover * amp + glowColor.rgb * bloom,
                   cover * amp + bloom) * qt_Opacity;
}
