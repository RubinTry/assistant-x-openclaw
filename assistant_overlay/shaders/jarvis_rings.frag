#version 320 es

precision highp float;

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform vec2 resolution;
layout(location = 1) uniform vec4 rotations;
layout(location = 2) uniform float pulseValue;
layout(location = 3) uniform float speakingScale;
layout(location = 4) uniform vec3 primaryColor;
layout(location = 5) uniform vec3 dimColor;
layout(location = 6) uniform vec3 lightColor;

const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;

float aa() {
  return 1.8 / min(resolution.x, resolution.y);
}

float ring(float radius, float target, float width) {
  return smoothstep(width + aa(), width - aa(), abs(radius - target));
}

float sector(float angle, float center, float halfWidth) {
  float d = abs(atan(sin(angle - center), cos(angle - center)));
  return smoothstep(halfWidth + aa() * 3.0, halfWidth - aa() * 3.0, d);
}

float repeatingSector(float angle, float count, float rotation, float halfWidth) {
  float cell = TAU / count;
  float local = mod(angle - rotation + cell * 0.5, cell) - cell * 0.5;
  return smoothstep(halfWidth + aa() * 3.0, halfWidth - aa() * 3.0, abs(local));
}

float angularBand(float angle, float count, float rotation, float duty) {
  float cell = TAU / count;
  float local = mod(angle - rotation, cell) / cell;
  float edge = aa() * 12.0;
  return smoothstep(0.0, edge, local) * smoothstep(duty, duty - edge, local);
}

float radialLine(float radius, float angle, float count, float rotation, float innerR, float outerR, float halfWidth) {
  float radial = smoothstep(innerR - aa(), innerR + aa(), radius)
    * smoothstep(outerR + aa(), outerR - aa(), radius);
  return radial * repeatingSector(angle, count, rotation, halfWidth);
}

float dotOnRing(vec2 uv, float angle, float radius, float size) {
  vec2 p = vec2(cos(angle), sin(angle)) * radius;
  return 1.0 - smoothstep(size, size + aa() * 6.0, length(uv - p));
}

vec3 blendLight(vec3 base, vec3 add, float amount) {
  return base + add * amount;
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy)
    / min(resolution.x, resolution.y);
  float radius = length(uv);
  float angle = atan(uv.y, uv.x);

  float outerRot = rotations.x;
  float arcsRot = rotations.y;
  float dataRot = rotations.z;
  float innerRot = rotations.w;
  float speak = clamp(speakingScale, 0.0, 1.0);
  float pulse = clamp(pulseValue, 0.0, 1.0);

  vec3 color = vec3(0.0);
  float alpha = 0.0;

  float outerRadius = 0.95 * (1.0 + speak * 0.02);
  float outerGlow = ring(radius, outerRadius, 0.020 + speak * 0.010);
  color = blendLight(color, primaryColor, outerGlow * (0.20 + pulse * 0.12 + speak * 0.40));
  alpha = max(alpha, outerGlow * (0.18 + pulse * 0.12 + speak * 0.35));

  float outerBase = ring(radius, 0.95, 0.010);
  color = blendLight(color, dimColor, outerBase * 0.45);
  alpha = max(alpha, outerBase * 0.42);

  float minorTicks = radialLine(radius, angle, 60.0, outerRot, 0.925, 0.952, 0.0045);
  color = blendLight(color, dimColor, minorTicks * 0.70);
  alpha = max(alpha, minorTicks * 0.55);

  float majorTicks = radialLine(radius, angle, 12.0, outerRot, 0.890, 0.955, 0.011);
  color = blendLight(color, primaryColor, majorTicks * 1.05);
  alpha = max(alpha, majorTicks * 0.86);

  float arcs1 = ring(radius, 0.82, 0.013) * angularBand(angle, 8.0, arcsRot, 0.065);
  float arcs2 = ring(radius, 0.75, 0.009) * angularBand(angle, 16.0, -arcsRot * 0.5, 0.045);
  float arcs3 = ring(radius, 0.68, 0.0065) * angularBand(angle, 24.0, arcsRot * 0.3, 0.033);
  color = blendLight(color, dimColor, arcs1 * 0.95);
  color = blendLight(color, primaryColor, arcs2 * 1.00);
  color = blendLight(color, lightColor, arcs3 * 0.78);
  alpha = max(alpha, arcs1 * 0.60);
  alpha = max(alpha, arcs2 * 0.78);
  alpha = max(alpha, arcs3 * 0.70);

  float dataBase = ring(radius, 0.55, 0.0065);
  float dataTicks = radialLine(radius, angle, 36.0, dataRot, 0.510, 0.555, 0.007);
  color = blendLight(color, primaryColor, dataBase * 0.70 + dataTicks * 0.90);
  alpha = max(alpha, dataBase * 0.58);
  alpha = max(alpha, dataTicks * 0.75);

  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    float bright = (sin(dataRot * 3.0 + fi) + 1.0) * 0.5;
    float dotMask = dotOnRing(uv, fi / 12.0 * TAU + dataRot, 0.505, 0.014 + bright * 0.006);
    color = blendLight(color, primaryColor, dotMask * (0.45 + bright * 0.55));
    alpha = max(alpha, dotMask * (0.42 + bright * 0.42));
  }

  float pulseRing = ring(radius, 0.55 * (1.02 + pulse * 0.02 + speak * 0.05), 0.010 + speak * 0.010);
  color = blendLight(color, primaryColor, pulseRing * (0.36 + pulse * 0.18 + speak * 0.44));
  alpha = max(alpha, pulseRing * (0.25 + pulse * 0.16 + speak * 0.45));

  float innerBase = ring(radius, 0.38, 0.009);
  float innerFine = ring(radius, 0.323, 0.0045);
  color = blendLight(color, primaryColor, innerBase * 0.98 + innerFine * 0.70);
  alpha = max(alpha, innerBase * 0.78);
  alpha = max(alpha, innerFine * 0.62);

  for (int i = 0; i < 8; i++) {
    float center = float(i) / 8.0 * TAU + innerRot;
    float chevron = sector(angle, center, 0.020)
      * smoothstep(0.240, 0.315, radius)
      * smoothstep(0.345, 0.320, radius);
    chevron += sector(angle, center + 0.035, 0.012)
      * smoothstep(0.250, 0.315, radius)
      * smoothstep(0.345, 0.320, radius) * 0.6;
    chevron += sector(angle, center - 0.035, 0.012)
      * smoothstep(0.250, 0.315, radius)
      * smoothstep(0.345, 0.320, radius) * 0.6;
    color = blendLight(color, lightColor, chevron * 0.90);
    alpha = max(alpha, chevron * 0.72);
  }

  for (int i = 0; i < 4; i++) {
    float dotMask = dotOnRing(uv, float(i) / 4.0 * TAU + innerRot * 0.5, 0.437, 0.017);
    color = blendLight(color, primaryColor, dotMask * 0.90);
    alpha = max(alpha, dotMask * 0.72);
  }

  float coreGlow = 1.0 - smoothstep(0.070 + speak * 0.010, 0.270 + speak * 0.080, radius);
  float coreFill = 1.0 - smoothstep(0.150, 0.153 + aa(), radius);
  float coreRing = ring(radius, 0.150, 0.008);
  float innerCore = 1.0 - smoothstep(0.072, 0.078 + aa(), radius);
  color = blendLight(color, primaryColor, coreGlow * (0.08 + pulse * 0.05 + speak * 0.18));
  color = mix(color, color + primaryColor * 0.18, coreFill * 0.35);
  color = blendLight(color, primaryColor, coreRing * 1.05);
  color = blendLight(color, lightColor, innerCore * 0.85);
  alpha = max(alpha, coreGlow * (0.10 + pulse * 0.05 + speak * 0.18));
  alpha = max(alpha, coreFill * 0.24);
  alpha = max(alpha, coreRing * 0.78);
  alpha = max(alpha, innerCore * 0.74);

  float scan = pow(max(0.0, sin(angle * 18.0 + radius * 30.0 + dataRot * 2.0)), 24.0);
  color = blendLight(color, primaryColor, scan * ring(radius, 0.60, 0.28) * 0.05);

  alpha = clamp(alpha, 0.0, 0.96);
  fragColor = vec4(color, alpha);
}
