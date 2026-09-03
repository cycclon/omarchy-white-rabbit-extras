#version 440

precision mediump float;

layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform Uni {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 resolution;
  float pitch;
  float scan;
  float vignette;
  float haze;
  float strength;
  float time;
};

void main() {
  vec2 coord = vTexCoord * resolution;
  float line = mod(coord.y, pitch);

  // One soft dark band per `pitch` rows: the band spans the middle 60% of
  // the pitch, so the pattern scales with thickness.
  float scanA = smoothstep(0.55 * pitch, 1.45 * pitch, line) * scan;

  // Tube edge falloff; corners sink the most.
  vec2 vd = vTexCoord - 0.5;
  float r = length(vd) * 1.7;
  float vigA = smoothstep(0.45, 1.0, r) * vignette;

  // Phosphor haze: faint green floor, held constant (the breathe was
  // removed at the user's request; keep `time` in the uniform block so the
  // QSB reflection layout stays unchanged).
  float hazeA = haze;
  vec3 hazeC = vec3(0.10, 0.62, 0.24);

  float a = min((scanA + vigA + hazeA) * strength, 0.85) * qt_Opacity;
  fragColor = vec4(hazeC * hazeA * strength * qt_Opacity, a);
}
