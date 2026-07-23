// Generated file – do not edit.
// ignore: constant_identifier_names
const String LightFS_glsl = r"""
#version 300 es

// uPointLights[0]：light0, light1
// light0: col0: positionRange(xyz:pos,w:range), col1: colorIntensity(rgb:color,a:intensity)
// light1: col2: positionRange(xyz:pos,w:range), col3: colorIntensity(rgb:color,a:intensity)
// same for uPointLights[1,2,3]
// uPointLights[1]：light2, light3
// uPointLights[2]：light4, light5
// uPointLights[3]：light6, light7
uniform mediump mat4 uPointLights[4];

uniform mediump ivec2 uPointLightCounts; // x=lightCount, y=shadowCastingCount

// UE4 windowed inverse-square attenuation (Karis 2013)
// +1.0 避免光源近距離過曝/firefly，rangeFade 讓光照在 radius 邊界平滑歸零
float calcAttenuation(float distSq, float radiusSq) {
    float ratio = distSq / radiusSq;
    float rangeFade = clamp(1.0 - ratio * ratio, 0.0, 1.0);
    return (rangeFade * rangeFade) / (distSq + 1.0);
}

vec3 calcPointLight(int i, vec3 fragPos, vec3 N, bool castShadow) {
    int matIndex = i / 2;      // 哪個 mat4
    int localIndex = i % 2;    // 該 mat4 裡的第幾盞燈

    mat4 m = uPointLights[matIndex];
    vec4 positionRangeSq = localIndex == 0 ? m[0] : m[2];
    vec4 colorIntensity = localIndex == 0 ? m[1] : m[3];

    vec3 lightPos = positionRangeSq.xyz;
    float radiusSq = positionRangeSq.w;

    vec3 L = lightPos - fragPos;
    L *= uInvObjScale;
    float distSq = dot(L, L);          // 用它算距離平方
    L = L * inversesqrt(max(distSq, 0.0001)); // 就地 normalize，覆寫成單位向量

    float atten = calcAttenuation(distSq, radiusSq);
    float NdotL = max(dot(N, L), 0.0);

    // colorIntensity: rgb -> lightColor, a -> lightIntensity
    vec3 radiance = colorIntensity.rgb * colorIntensity.a * atten * NdotL;

    if (castShadow) {
        // TODO: DPSM shadow lookup 接進來
        // float shadow = sampleDPSMShadow(i, fragPos, lightPos);
        // radiance *= shadow;
    }

    return radiance;
}

// point lights lighting in object space
lowp vec3 CalculateLighting(vec3 fragPos, vec3 N) {
    vec3 result = vec3(0.0);
    int lightCount = uPointLightCounts.x;
    int shadowCount = uPointLightCounts.y;

    for (int i = 0; i < lightCount; i++) {
        bool castShadow = i < shadowCount;
        result += calcPointLight(i, fragPos, N, castShadow);
    }
    return result;
}

""";
