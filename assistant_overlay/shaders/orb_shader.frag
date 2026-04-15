#version 320 es

precision highp float;

layout(location = 0) out vec4 fragColor;

uniform float time;
uniform vec2 resolution;

float Ellipse(vec2 UV, float Width, float Height) {
    float d = length(((UV * 2.0) - vec2(1.0)) / vec2(Width, Height));
    return clamp((1.0 - d) / d, 0.0, 1.0);
}

void main() {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);

    vec2 uv2 = uv;

    // sphere projection (scale up UV to shrink sphere by 1/3)
    float sphereScale = 1.5; // 1 / (2/3) = 1.5
    float le = length(uv2 * sphereScale);
    float le2 = le < 1.0 ? le : 0.0;
    float as = tan(asin(le2));
    as *= 0.196;
    vec2 n = normalize(uv2 * sphereScale);
    as *= as;
    n *= as;

    // slow breathing
    float breathScale = 0.9 + sin(time * 0.3) * 0.012;

    // colors — pink/purple/cyan palette
    vec4 color1 = vec4(1.0, 0.42, 0.62, 1.0);
    vec4 color2 = vec4(0.77, 0.30, 1.0, 1.0) * 1.8;
    vec4 color3 = vec4(0.30, 0.79, 0.96, 1.0) * 2.5;
    vec4 color4 = vec4(0.63, 0.16, 0.80, 1.0) * 1.4;
    vec4 color5 = vec4(1.0, 0.65, 0.80, 1.0) * 1.1;

    float ssc = breathScale;

    // slow animation 0.25x
    float t = time * 0.25;

    vec2 fnR = vec2(fract(n.x + cos(t) * 1.1), fract(n.y + 0.325 + t * 0.21));
    float c1 = Ellipse(fnR, 0.645 * ssc, 0.85);
    float c1b = Ellipse(vec2(fract((n.x * -1.0 + 0.5) + cos(t) * 1.1), fnR.y), 0.645, 0.85);
    c1 = max(c1, 0.9 * c1b);

    vec2 fnG = vec2(fract(n.x + t * 0.521), fract(n.y + 0.125 + sin(t) * 1.421));
    float c2 = Ellipse(fnG, 0.6145, 0.95);

    vec2 fnB = vec2(fract(n.x + t * 0.1521), fract(n.y + 0.125 + cos(t) * 2.421));
    float c3 = Ellipse(fnB, 0.6145 * ssc, 0.795);

    vec2 fnY = vec2(fract(n.x + t * 0.3521), fract(n.y + 0.125 + sin(cos(t) * 2.421)));
    float c4 = Ellipse(fnY, 0.6145, 0.795);

    vec2 fnY2 = vec2(fract(n.x + t * 0.7521), fract(n.y + 0.125 + t * 1.421));
    float c5 = Ellipse(fnY2, 0.2145, 0.895);

    // soft circular mask (colors and alpha fade together)
    float circleMask = 1.0 - smoothstep(0.93, 1.0, le);

    color1 *= c1 * circleMask;
    color2 *= c2 * circleMask;
    color3 *= c3 * circleMask;
    color4 *= c4 * circleMask;
    color5 *= c5 * circleMask;

    vec4 outColor = color1 + color2 + color3 + color4 + color5;

    // soft glow just outside sphere edge
    float edgeGlow = exp(-max(0.0, le - 0.9) * 10.0) * 0.0;
    vec3 glowCol = mix(vec3(1.0, 0.42, 0.62), vec3(0.77, 0.30, 1.0), le * 0.5);
    vec3 sphereCol = outColor.rgb;

    vec3 finalCol = sphereCol + glowCol * edgeGlow;
    float alpha = circleMask;
    alpha = clamp(alpha, 0.0, 1.0);

    fragColor = vec4(finalCol, alpha);
}