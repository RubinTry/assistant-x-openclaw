#version 300 es
// Fog frag-shader: ES3 //////////
// must append to fragment shader

// sphere fog base on camera position
in highp float fogDist; // distance to camera

// x: sphereStart, y: sphereDepth, z: planeHeight
uniform mediump vec3 uFogParams;
uniform lowp vec3 uFogColor;

// plane fog
uniform mediump vec4 uPlaneFog;
uniform lowp vec3 uPlaneFogColor;

lowp vec4 ApplyFog(in lowp vec4 texResult)
{
    mediump float fogDensity;
    mediump float fogBlend;
    lowp vec4 result = texResult;
    // 1/2: plane fog
    if (uFogParams.z > 0.0) {
        mediump float planeDist = dot(uPlaneFog.xyz, ObjectspaceV) + uPlaneFog.w;
        fogDensity = clamp(planeDist / uFogParams.z, 0.0, 1.0);
        fogBlend = clamp(fogDensity + 1.0 - texResult.a, 0.0, 1.0);
        result = vec4(mix(result.rgb, uPlaneFogColor, fogBlend), texResult.a);
    }
    // 2/2: sphere fog
    if (uFogParams.y > 0.0) {
        fogDensity = clamp((fogDist - uFogParams.x) / uFogParams.y, 0.0, 1.0);
        fogBlend = clamp(fogDensity + 1.0 - texResult.a, 0.0, 1.0);
        result = vec4(mix(result.rgb, uFogColor, fogBlend), texResult.a);
    }
    return result;
}
