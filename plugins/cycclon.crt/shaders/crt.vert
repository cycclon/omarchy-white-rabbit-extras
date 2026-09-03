#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

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

layout(location = 0) out vec2 vTexCoord;

void main() {
  vTexCoord = qt_MultiTexCoord0;
  gl_Position = qt_Matrix * qt_Vertex;
}
