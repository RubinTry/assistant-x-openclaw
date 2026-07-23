#version 320 es
precision highp float;

// ═══════════════════════════════════════════════════════════════════════
//  J.A.R.V.I.S. Unified Shader — raymarched 3D + particle systems
//
//  Translates V1 ParticleWindow.swift (SceneKit) → single GLSL ES 3.20
//
//  Layers in render order:
//    1. Raymarched 3D: central core sphere + 3 tilted rings + veils
//    2. Orbit particles: data-flow dots circling ring paths
//    3. Ambient cloud: outer noise-field particle mist
//    4. Stray sparkles: scattered blinking particles near core
//    5. Background glow + vignette
//
//  States (uState): 0=idle(teal) 1=listening(gold) 2=thinking(silver)
//                    3=speaking(bright teal) 4=executing(orange)
// ═══════════════════════════════════════════════════════════════════════

layout(location = 0) out vec4 fragColor;

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2  uResolution;   // vec2 uses loc 1,2
layout(location = 3) uniform int   uState;
layout(location = 4) uniform float uEnergy;
layout(location = 5) uniform float uOpacity;
layout(location = 6) uniform float uFocusBoost;

// ── Constants ────────────────────────────────────────────────────────

const float PI        = 3.14159265359;
const int   MAX_STEPS = 48;
const float MAX_DIST  = 16.0;
const float SURF_DIST = 0.0008;
const float EPS       = 0.002;

const vec3  R0_AXIS = vec3(0.2, 1.0, 0.0);
const float R0_R    = 1.30;
const float R0_PER  = 7.0;

const vec3  R1_AXIS = vec3(1.0, 0.15, 0.0);
const float R1_R    = 1.10;
const float R1_PER  = 9.5;

const vec3  R2_AXIS = vec3(0.0, 0.20, 1.0);
const float R2_R    = 1.40;
const float R2_PER  = 11.0;

const float CORE_R  = 0.35;
const float GLOW_R  = 0.60;
const float WIRE_W  = 0.009;
const float VEIL_W  = 0.15;  // fraction of ring radius (6%+3%+6%)

// ── Colors (V1 palette) ─────────────────────────────────────────────

const vec3 TEAL   = vec3(0.49, 0.77, 0.78);
const vec3 TEAL_B = vec3(0.49, 0.82, 0.83);
const vec3 GOLD   = vec3(1.00, 0.67, 0.06);
const vec3 SILVER = vec3(0.74, 0.78, 0.92);
const vec3 ORANGE = vec3(0.94, 0.44, 0.06);

vec3 coreCol() {
    if (uState == 1) return GOLD;
    if (uState == 2) return SILVER;
    if (uState == 3) return TEAL_B;
    if (uState == 4) return ORANGE;
    return TEAL;
}

vec3 ringCol() {
    if (uState == 1) return GOLD * 0.85;
    if (uState == 2) return SILVER * 0.90;
    if (uState == 3) return TEAL_B * 0.85;
    if (uState == 4) return ORANGE * 0.85;
    return TEAL * 0.85;
}

vec3 veilCol() {
    if (uState == 1) return GOLD * 0.70;
    if (uState == 2) return SILVER * 0.75;
    if (uState == 3) return TEAL_B;
    if (uState == 4) return ORANGE * 0.80;
    return TEAL;
}

vec3 partCol() {
    if (uState == 1) return GOLD * 0.55;
    if (uState == 2) return SILVER * 0.60;
    if (uState == 3) return TEAL_B * 0.45;
    if (uState == 4) return ORANGE * 0.60;
    return TEAL;
}

// ── Hash / noise ────────────────────────────────────────────────────

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i+vec2(1,0)), f.x),
               mix(hash2(i+vec2(0,1)), hash2(i+vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5, freq = 1.0;
    for (int i = 0; i < 4; i++) { v += a * noise(p * freq); freq *= 2.1; a *= 0.5; }
    return v;
}

// ── Rotation helpers ────────────────────────────────────────────────

mat3 rotAxis(vec3 axis, float a) {
    axis = normalize(axis);
    float s = sin(a), c = cos(a), oc = 1.0 - c;
    return mat3(
        oc*axis.x*axis.x+c,       oc*axis.x*axis.y-axis.z*s, oc*axis.z*axis.x+axis.y*s,
        oc*axis.x*axis.y+axis.z*s, oc*axis.y*axis.y+c,       oc*axis.y*axis.z-axis.x*s,
        oc*axis.z*axis.x-axis.y*s, oc*axis.y*axis.z+axis.x*s, oc*axis.z*axis.z+c);
}

// ── SDF ─────────────────────────────────────────────────────────────

float sdSphere(vec3 p, float r) { return length(p) - r; }
float sdTorus(vec3 p, vec2 t) { vec2 q=vec2(length(p.xz)-t.x,p.y); return length(q)-t.y; }

// ── Wave deformation (matches V1 buildVeil) ────────────────────────

float asymSin(float x, float skew) { return sin(x) + skew * sin(2.0*x); }
float ringWave(float a, float e) {
    if (e < 0.003) return 0.0;
    float d = sqrt(e) * 0.50;
    return max(0.0, asymSin(a*8.0+uTime*1.2,0.35)*d + asymSin(a*10.0+uTime*1.6,0.25)*d*0.35 + asymSin(a*14.0+uTime*2.0,0.15)*d*0.15);
}

// ── Breathing ───────────────────────────────────────────────────────

float breath() {
    if (uState != 0) return 1.0;
    float ph = mod(uTime/7.0, 1.0);
    return ph<0.42 ? 1.0+sin(ph/0.42*PI*0.5)*0.015 : 1.0+sin((ph-0.42)/0.58*PI*0.5+PI*0.5)*0.015;
}

// ── Scene geometry ──────────────────────────────────────────────────

// mat: 0=core 1=wire 2=veil, ring: -1 or 0/1/2
struct Hit { float d; int m; int r; };

Hit map(vec3 p, float e) {
    float bs = breath();
    vec3 pc = p / bs;
    float dCore = sdSphere(pc, CORE_R);
    float dGlow = sdSphere(pc, GLOW_R);

    Hit h;
    h.d = dCore; h.m = 0; h.r = -1;
    if (dGlow < h.d) { h.d = dGlow; h.m = 0; h.r = -1; }

    vec3  ax[3] = vec3[3](R0_AXIS, R1_AXIS, R2_AXIS);
    float rd[3] = float[3](R0_R, R1_R, R2_R);
    float pr[3] = float[3](R0_PER, R1_PER, R2_PER);

    for (int i = 0; i < 3; i++) {
        mat3 rm = rotAxis(ax[i], uTime * 2.0 * PI / pr[i]);
        vec3 lp = rm * p;
        float a = atan(lp.y, lp.x);
        float r = rd[i] + ringWave(a, e);

        float dw = sdTorus(lp, vec2(r, WIRE_W));
        if (dw < h.d) { h.d = dw; h.m = 1; h.r = i; }

        float dv = sdTorus(lp, vec2(r, r * VEIL_W));
        if (dv + 0.002 < h.d) { h.d = dv; h.m = 2; h.r = i; }
    }
    return h;
}

vec3 normal(vec3 p, float e) {
    vec2 ep = vec2(EPS, 0);
    return normalize(vec3(map(p+ep.xyy,e).d-map(p-ep.xyy,e).d,
                          map(p+ep.yxy,e).d-map(p-ep.yxy,e).d,
                          map(p+ep.yyx,e).d-map(p-ep.yyx,e).d));
}

float shadow(vec3 ro, vec3 rd, float mi, float ma, float k, float e) {
    float res = 1.0;
    for (float d = mi; d < ma;) {
        float h = map(ro+rd*d, e).d;
        if (h < SURF_DIST) return 0.0;
        res = min(res, k*h/d);
        d += max(h, 0.02);
    }
    return res;
}

// ── Raymarch ────────────────────────────────────────────────────────

Hit march(vec3 ro, vec3 rd, float e) {
    float t = 0.0;
    Hit hit; hit.d = MAX_DIST; hit.m = -1; hit.r = -1;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t;
        Hit h = map(p, e);
        if (h.d < SURF_DIST) { hit.d = t; hit.m = h.m; hit.r = h.r; break; }
        t += h.d;
        if (t > MAX_DIST) break;
    }
    return hit;
}

// ── 3D scene render ────────────────────────────────────────────────

vec4 shade(vec3 ro, vec3 rd, float e) {
    Hit hit = march(ro, rd, e);
    if (hit.m < 0) return vec4(0, 0, 0, 0);

    vec3 p = ro + rd * hit.d;
    vec3 n = normal(p, e);
    vec3 ld = normalize(vec3(1.5, 2.0, -3.0));
    vec3 vd = normalize(ro - p);

    float diff = max(dot(n, ld), 0.0) * 0.6 + 0.4;
    float spec = pow(max(dot(normalize(ld+vd), n), 0.0), 64.0) * 0.4;
    float rim  = pow(1.0 - abs(dot(n, vd)), 3.0);
    float sh   = shadow(p + n*0.01, ld, 0.02, 4.0, 8.0, e);

    vec3 col; float alpha;

    if (hit.m == 0) {
        col = coreCol();
        float bloom = 0.35;
        if (uState == 1) bloom = 0.65; else if (uState == 2) bloom = 0.45;
        else if (uState == 3) bloom = 0.55; else if (uState == 4) bloom = 0.72;
        bloom += e * 0.15 * (1.0 + uFocusBoost * 0.4);

        col = col * (diff * sh + 0.15) + vec3(1.0)*spec*sh + col*rim*0.5 + col * (1.0 + bloom);
        alpha = 1.0;
    } else if (hit.m == 1) {
        col = ringCol();
        col = col * (diff * sh + 0.35) + vec3(1.0)*spec*sh*0.5 + col*rim*0.3 + col * (0.35 + e*0.2);
        alpha = 0.9;
    } else {
        col = veilCol();
        col = col * 0.25 + col * rim * 0.3 + col * 0.08;
        // distance-based alpha gradient (V1 3-layer veil)
        alpha = 0.04 + smoothstep(VEIL_W * 1.5, 0.0, abs(hit.d)) * 0.12;
        alpha *= 0.6 + e * 0.8;
    }

    // bloom falloff from core
    float cd = length(p / breath());
    col += coreCol() * exp(-cd*cd*2.5) * 0.5;

    return vec4(col, alpha);
}

// ── 2D particle glow helper ────────────────────────────────────────

float glow(vec2 uv, vec2 pos, float sz) { return exp(-dot(uv-pos,uv-pos)/(sz*sz*0.12)); }

// ── Main ────────────────────────────────────────────────────────────

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5*uResolution) / min(uResolution.x, uResolution.y);
    float aspect = uResolution.x / uResolution.y;

    float e = uEnergy * (uFocusBoost > 0.5 ? 1.4 : 1.0);

    // ── Camera (3D perspective) ────────────────────────────────────
    vec3 ro = vec3(0.0, 0.25, -7.5);
    vec3 fwd = normalize(vec3(0,0,0) - ro);
    vec3 rgt = normalize(cross(fwd, vec3(0,1,0)));
    vec3 up  = cross(rgt, fwd);
    vec3 rd = normalize(uv.x*rgt + uv.y*up + fwd*(1.0/0.6));

    // ── Pass 1: Raymarched 3D scene ────────────────────────────────
    vec4 scene = shade(ro, rd, e);
    vec3 col = scene.rgb;
    float alpha = scene.a * uOpacity;

    // ── Pass 2: Orbit particles (data flow along rings) ────────────
    vec3 pcol = partCol();
    float ringR[3] = float[3](R0_R, R1_R, R2_R);

    for (int ring = 0; ring < 3; ring++) {
        float rr = ringR[ring];
        int n = 16 + ring * 6;
        for (int j = 0; j < 24; j++) {
            if (j >= n) break;
            float s = float(j)*0.17 + float(ring)*0.43;
            // project 3D ring position to 2D screen
            float a3 = s*6.2831 + uTime*(0.5+float(ring)*0.2);
            // approximate projection: ring ellipse in screen space
            float ax = 0.7 + float(ring)*0.1;
            float ay = 0.85 - float(ring)*0.05;
            vec2 rp = vec2(rr*ax*cos(a3), rr*ay*sin(a3));
            float sz = 0.012 + hash2(vec2(s,0.77))*0.014;
            float br = 0.4 + hash2(vec2(s,0.5))*0.6;
            float g = glow(uv*2.0, rp*2.0, sz) * br;
            col += pcol * g * 0.7 * (0.4 + e*1.0);
        }
    }

    // ── Pass 3: High-speed inner data stream ───────────────────────
    float inR[3] = float[3](0.55, 0.62, 0.50);
    for (int ring = 0; ring < 3; ring++) {
        float rr = inR[ring];
        for (int j = 0; j < 16; j++) {
            float s = float(j)*0.23 + float(ring)*0.57;
            float a3 = s*6.2831 + uTime*(0.9+float(ring)*0.3);
            vec2 rp = vec2(rr*cos(a3), rr*0.85*sin(a3));
            float sz = 0.007 + hash2(vec2(s,0.3))*0.010;
            float br = 0.5 + hash2(vec2(s,0.9))*0.5;
            float g = glow(uv*2.0, rp*2.0, sz) * br;
            col += pcol * 1.2 * g * (0.5 + e*1.3);
        }
    }

    // ── Pass 4: Ambient noise-cloud particles ──────────────────────
    float cloud = 0.0;
    for (float r = 1.2; r < 3.5; r += 0.35) {
        vec2 nu = uv * r * 3.2;
        cloud += fbm(nu + vec2(uTime*0.06, uTime*0.04)) * 0.13;
        cloud += fbm(nu*1.25 - vec2(uTime*0.04, uTime*0.06) + 5.7) * 0.11;
    }
    float cmask = smoothstep(0.55, 0.78, clamp(cloud, 0.0, 1.0)) * (0.25 + e*1.2);
    col += pcol * cmask * 0.6;

    // ── Pass 5: Stray sparkles near core ───────────────────────────
    for (int i = 0; i < 12; i++) {
        float s = float(i)*0.33;
        float a = hash2(vec2(s, uTime*0.3))*6.2831;
        float d = 0.2 + hash2(vec2(s, uTime*0.22+1.0))*1.3;
        vec2 sp = vec2(cos(a), sin(a))*d;
        float lf = fract(s*3.7 + uTime*(0.12+hash2(vec2(s,0.0))*0.18));
        float bl = smoothstep(0.0,0.15,lf)*smoothstep(1.0,0.85,lf);
        float sz = 0.005 + bl*0.007;
        float g = glow(uv*2.5, sp*2.5, sz) * (0.35+hash2(vec2(s,2.0))*0.65) * bl;
        col += coreCol() * g * 0.5;
    }

    // ── Pass 6: Scattered blink particles ──────────────────────────
    for (int i = 0; i < 20; i++) {
        float s = float(i)*0.19;
        float lf = fract(s*3.7 + uTime*(0.13+hash2(vec2(s,0.0))*0.17));
        float a = hash2(vec2(s, floor(uTime*0.25+s)))*6.2831;
        float d = 0.4 + hash2(vec2(s,1.0))*2.6;
        vec2 sp = vec2(cos(a), sin(a))*d;
        float bl = smoothstep(0.0,0.12,lf)*smoothstep(1.0,0.88,lf);
        float sz = 0.004 + bl*0.005;
        float g = glow(uv*2.0, sp*2.0, sz) * (0.3+hash2(vec2(s,2.0))*0.7) * bl;
        col += pcol * g * 0.45 * (0.3 + e*0.8);
    }

    // ── Post: background glow ──────────────────────────────────────
    float dc = length(uv) * 2.2;
    float bgGlow = exp(-dc*dc*2.5);
    col += coreCol() * bgGlow * 0.12 * (1.0 + e*2.0);

    // ── Post: vignette ─────────────────────────────────────────────
    col *= 1.0 - dc * 0.22;

    // ── Post: energy flash ─────────────────────────────────────────
    col *= 1.0 + e * 0.25;

    // ── Final alpha ────────────────────────────────────────────────
    float edge = smoothstep(1.7, 0.5, dc);
    float finalAlpha = max(alpha, (bgGlow*0.35 + cmask*2.0) * uOpacity);
    finalAlpha = max(finalAlpha * edge, 0.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), finalAlpha);
}
