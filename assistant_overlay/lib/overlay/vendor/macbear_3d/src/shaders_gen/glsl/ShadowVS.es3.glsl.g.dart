// Generated file – do not edit.
// ignore: constant_identifier_names
const String ShadowVS_glsl = r"""
#version 300 es
// Shadow vert-shader ES3 //////////
// must insert before vertex shader

#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
uniform highp float NormalBias;

#ifdef ENABLE_SHADOW_MAP
uniform mat4 MatrixShadowmap;
out highp vec4 LightcoordShadowmap;
#endif // ENABLE_SHADOW_MAP

#ifdef ENABLE_SHADOW_CSM
uniform mat4 MatrixCSM[4];
out highp vec4 LightcoordCSM[4];
#endif // ENABLE_SHADOW_CSM

void ComputeShadowPosition(in highp vec3 objVert, in mediump vec3 objNormal)
{
    vec4 biasedVert = vec4(objVert + objNormal * NormalBias, 1.0);

#ifdef ENABLE_SHADOW_MAP
    LightcoordShadowmap = MatrixShadowmap * biasedVert;
#endif // ENABLE_SHADOW_MAP
    
#ifdef ENABLE_SHADOW_CSM
    LightcoordCSM[0] = MatrixCSM[0] * biasedVert;
    LightcoordCSM[1] = MatrixCSM[1] * biasedVert;
    LightcoordCSM[2] = MatrixCSM[2] * biasedVert;
    LightcoordCSM[3] = MatrixCSM[3] * biasedVert;
#endif // ENABLE_SHADOW_CSM
}

#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM

""";
