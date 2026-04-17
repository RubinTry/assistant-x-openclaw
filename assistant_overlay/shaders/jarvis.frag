#version 320 es
precision highp float;
uniform float outerRingRotation;
uniform vec2 resolution;
uniform float arcsRotation;
uniform float dataRingRotation;
uniform float innerRingRotation;
uniform float pulseValue;
uniform float speakingScale;
uniform float effectState;
out vec4 fragColor;
const float PI = 3.14159265359;
const float TAU = 6.28318530718;
float sdRing(vec2 p, float r, float w) { return abs(length(p) - r) - w * 0.5; }
float sdSegment(vec2 p, vec2 a, vec2 b, float w) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - w * 0.5;
}
float sdLineCap(vec2 p, vec2 a, vec2 b, float w) {
    float d = sdSegment(p, a, b, w);
    d = min(d, length(p - a) - w * 0.5);
    d = min(d, length(p - b) - w * 0.5);
    return d;
}
float sdArcSeg(vec2 p, float r, float sa, float al, float w) {
    float a = mod(atan(p.y, p.x) - sa + TAU, TAU);
    float inA = step(0.0, a) * (1.0 - step(al, a));
    float d = abs(length(p) - r) - w * 0.5;
    return mix(1e10, d, inA);
}
float sdChevron(vec2 p, vec2 c, float a, float sz, float w) {
    vec2 dir = vec2(cos(a), sin(a));
    vec2 perp = vec2(-dir.y, dir.x);
    vec2 p1 = c + perp * sz;
    vec2 p2 = c - perp * sz;
    float d1 = sdLineCap(p, p1, c, w);
    float d2 = sdLineCap(p, c, p2, w);
    return min(d1, d2);
}
void main() {
    vec2 uv = gl_FragCoord.xy - resolution * 0.5;
    float maxR = resolution.x * 0.5;
    float r = length(uv);
    float alpha = 0.0;
    float glow = 0.0;
    float outerR = maxR * 0.95;

    float d = sdRing(uv, outerR, 10.0);
    alpha += (1.0 - smoothstep(-2.0, 2.0, d));
    glow += exp(-max(d, 0.0) * 1.0) * 0.5;

    for (int i = 0; i < 60; i++) {
        float angle = float(i) / 60.0 * TAU + outerRingRotation;
        vec2 dir = vec2(cos(angle), sin(angle));
        float d = sdLineCap(uv, dir * (outerR - 5.0), dir * outerR, 2.0);
        alpha += (1.0 - smoothstep(-0.5, 0.5, d));
    }
    for (int i = 0; i < 12; i++) {
        float angle = float(i) / 12.0 * TAU + outerRingRotation;
        vec2 dir = vec2(cos(angle), sin(angle));
        float d = sdLineCap(uv, dir * (outerR - 12.0), dir * outerR, 4.0);
        alpha += (1.0 - smoothstep(-1.0, 1.0, d));
        glow += exp(-max(d, 0.0) * 1.0) * 0.5;
    }
    float arc1R = maxR * 0.82;
    for (int i = 0; i < 8; i++) {
        float angle = float(i) / 8.0 * TAU + arcsRotation;
        float d = sdArcSeg(uv, arc1R, angle, PI / 12.0, 6.0);
        alpha += (1.0 - smoothstep(-1.5, 1.5, d));
        glow += exp(-max(d, 0.0) * 0.8) * 0.2;
    }
    float arc2R = maxR * 0.75;
    for (int i = 0; i < 16; i++) {
        float angle = float(i) / 16.0 * TAU - arcsRotation * 0.5;
        float d = sdArcSeg(uv, arc2R, angle, PI / 20.0, 4.0);
        alpha += (1.0 - smoothstep(-1.0, 1.0, d));
    }
    float arc3R = maxR * 0.68;
    for (int i = 0; i < 24; i++) {
        float angle = float(i) / 24.0 * TAU + arcsRotation * 0.3;
        float d = sdArcSeg(uv, arc3R, angle, PI / 30.0, 3.0);
        alpha += (1.0 - smoothstep(-0.75, 0.75, d));
    }
    float dataR = maxR * 0.55;
    d = sdRing(uv, dataR, 3.0);
    alpha += (1.0 - smoothstep(-0.75, 0.75, d));
    glow += exp(-max(d, 0.0) * 1.0) * 0.25;
    for (int i = 0; i < 36; i++) {
        float angle = float(i) / 36.0 * TAU + dataRingRotation;
        vec2 dir = vec2(cos(angle), sin(angle));
        float d = sdLineCap(uv, dir * (dataR - 8.0), dir * dataR, 2.5);
        alpha += (1.0 - smoothstep(-0.5, 0.5, d));
    }
    for (int i = 0; i < 12; i++) {
        float angle = float(i) / 12.0 * TAU + dataRingRotation;
        float dotR = dataR - 15.0;
        vec2 dotCenter = vec2(cos(angle), sin(angle)) * dotR;
        float brightness = 0.5 + 0.5 * abs(sin(dataRingRotation * 3.0 + float(i)));
        float dotD = length(uv - dotCenter) - (4.0 + brightness * 2.0);
        float dotA = 0.59 + brightness * 0.41;
        alpha += (1.0 - smoothstep(-1.5, 1.5, dotD)) * dotA;
    }
    float pulseRingAlpha = (80.0 + pulseValue * 50.0 + speakingScale * 100.0) / 255.0;
    float pulseRingR = dataR * (1.02 + pulseValue * 0.02 + speakingScale * 0.05);
    float pulseW = 4.0 + speakingScale * 3.0;
    d = sdRing(uv, pulseRingR, pulseW);
    alpha += (1.0 - smoothstep(-1.0, 1.0, d)) * pulseRingAlpha * 2.0;
    float innerR = maxR * 0.38;
    d = sdRing(uv, innerR, 4.0);
    alpha += (1.0 - smoothstep(-1.0, 1.0, d));
    glow += exp(-max(d, 0.0) * 1.0) * 0.25;
    d = sdRing(uv, innerR * 0.85, 2.0);
    alpha += (1.0 - smoothstep(-0.5, 0.5, d));
    float chevronSize = maxR * 0.06;
    float chevronR = innerR * 0.7;
    for (int i = 0; i < 8; i++) {
        float angle = float(i) / 8.0 * TAU + innerRingRotation;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec2 center = dir * chevronR;
        float d = sdChevron(uv, center, angle, chevronSize, 3.0);
        alpha += (1.0 - smoothstep(-0.75, 0.75, d));
    }
    float dotR2 = innerR * 1.15;
    for (int i = 0; i < 4; i++) {
        float angle = float(i) / 4.0 * TAU + innerRingRotation * 0.5;
        vec2 dotCenter = vec2(cos(angle), sin(angle)) * dotR2;
        float d = length(uv - dotCenter) - 5.0;
        alpha += (1.0 - smoothstep(-1.0, 1.0, d));
    }
    float coreR = maxR * 0.15;
    float coreGlowAlpha = (20.0 + pulseValue * 15.0 + speakingScale * 50.0) / 255.0;
    float coreGlowR = coreR * (1.8 + speakingScale * 0.5);
    d = length(uv) - coreGlowR;
    glow += exp(-max(d, 0.0) * 0.5) * coreGlowAlpha * 2.0;
    d = length(uv) - coreR;
    alpha += (1.0 - step(0.0, d)) * 0.235;
    d = abs(length(uv) - coreR) - 1.5;
    alpha += (1.0 - smoothstep(-0.375, 0.375, d));
    d = length(uv) - coreR * 0.5;
    alpha += (1.0 - smoothstep(-0.75, 0.75, d));
    alpha = clamp(alpha, 0.0, 1.0);
    glow = clamp(glow, 0.0, 1.0);
    float edgeFade = 1.0 - smoothstep(maxR * 0.85, maxR, r);
    alpha *= edgeFade;
    float totalAlpha = clamp(alpha + glow * 0.7, 0.0, 1.0);
    vec3 baseCol;
    if (effectState < 0.5) {
        baseCol = vec3(0.5, 0.95, 1.0);
    } else if (effectState < 1.5) {
        baseCol = vec3(0.5, 1.0, 0.7);
    } else {
        baseCol = vec3(1.0, 0.4, 0.4);
    }
    fragColor = vec4(baseCol * totalAlpha, totalAlpha);
}