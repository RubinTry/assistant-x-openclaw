#version 320 es

precision highp float;

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform float time;
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform vec3 coreColor;
layout(location = 3) uniform vec3 glowColor;
layout(location = 4) uniform vec3 accentColor;
layout(location = 5) uniform vec3 mistColor;
layout(location = 6) uniform float orbScale;

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec2 mod289(vec2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute(vec3 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

float snoise(vec2 v) {
  const vec4 c = vec4(
    0.211324865405187,
    0.366025403784439,
    -0.577350269189626,
    0.024390243902439
  );

  vec2 i = floor(v + dot(v, c.yy));
  vec2 x0 = v - i + dot(i, c.xx);
  vec2 i1 = x0.x > x0.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + c.xxzz;
  x12.xy -= i1;
  i = mod289(i);

  vec3 p = permute(
    permute(i.y + vec3(0.0, i1.y, 1.0))
      + i.x + vec3(0.0, i1.x, 1.0)
  );
  vec3 m = max(
    0.5 - vec3(
      dot(x0, x0),
      dot(x12.xy, x12.xy),
      dot(x12.zw, x12.zw)
    ),
    0.0
  );
  m = m * m;
  m = m * m;

  vec3 x = 2.0 * fract(p * c.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float ring(float value, float size, float softness) {
  return smoothstep(softness, 0.0, abs(value - size));
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy)
    / min(resolution.x, resolution.y);
  float t = time * 0.72;
  float dist = length(uv);
  float angle = atan(uv.y, uv.x);
  vec2 circularNoise = vec2(cos(angle), sin(angle));

  float livingEdge =
    snoise(circularNoise * 1.65 + t * 0.48) * 0.07
    + snoise(circularNoise * 4.80 - t * 0.92) * 0.032
    + snoise(circularNoise * 10.0 + vec2(t * 0.38, -t * 0.22)) * 0.012;
  float pulse = sin(t * 1.25) * 0.008 + sin(t * 0.37) * 0.012;
  float radius = (0.48 + livingEdge + pulse) * orbScale;
  float edge = abs(dist - radius);

  float fineCore = 0.006 / (edge + 0.007);
  float softAura = 0.018 / (edge + 0.045);
  float innerMist = smoothstep(radius, 0.0, dist) * 0.055;
  float filament =
    ring(dist, radius + sin(angle * 8.0 + t * 1.4) * 0.012, 0.012)
    * (0.45 + 0.55 * snoise(circularNoise * 7.0 + t));

  vec3 color = vec3(0.0);
  color += coreColor * fineCore * 0.55;
  color += glowColor * softAura * 0.72;
  color += accentColor * filament * 0.16;
  color += mistColor * innerMist;

  float centerHorizon = smoothstep(0.35, 0.0, dist);
  color *= 1.0 - centerHorizon * 0.58;
  color *= smoothstep(1.42, 0.08, dist);

  // Leave only a restrained cool-blue breath immediately outside the living
  // edge. It fades quickly enough to avoid becoming a broad neon halo.
  float outerMask = 1.0 - smoothstep(radius + 0.012, radius + 0.050, dist);
  color *= outerMask;

  color = 1.0 - exp(-color * 1.42);
  color = pow(color, vec3(0.88));

  float alpha = clamp(length(color) * 1.35, 0.0, 1.0);
  fragColor = vec4(color, alpha);
}
