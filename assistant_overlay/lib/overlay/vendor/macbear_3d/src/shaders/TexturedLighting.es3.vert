#version 300 es
// TexturedLighting vert-shader: ES3 //////////
// 1. 'glsl/Skinning.es3.vert' inserted here
// 2. 'glsl/Shadow.es3.vert' inserted here
// 3. define ENABLE_FOG for fog

#ifndef ENABLE_SKINNING
layout(location = 0) in highp vec3 inVertex;
layout(location = 2) in mediump vec3 inNormal;
#endif // ENABLE_SKINNING

layout(location = 3) in mediump vec2 inTexCoord;
uniform lowp vec4 uColor;

out highp vec3 ObjectspaceV;    // Object space Vertex

#ifdef ENABLE_PIXEL_LIGHTING
out mediump vec3 ObjectspaceN;
#else
uniform lowp vec4 ColorDiffuse;
uniform mediump vec4 ColorSpecular;
out lowp vec4 SpecularOut;
#endif // ENABLE_PIXEL_LIGHTING

uniform lowp vec3 ColorAmbient;
uniform mediump vec3 uEyePos;
uniform mediump vec3 uLightDir;
uniform mediump vec3 uInvObjScale;

out lowp vec4 DestinationColor;
out mediump vec2 TextureCoordOut;

uniform mat4 ModelviewProjection;

#ifdef ENABLE_FOG
out highp float fogDist;   // distance: eye to obj-vertex
#endif // ENABLE_FOG

void main(void)
{
    highp vec4 objVert = vec4(inVertex, 1.0);
    mediump vec3 objNormal = inNormal;
    
#ifdef ENABLE_SKINNING
    if (BoneCount > 0)
    {
        ComputeSkinningVertex(objVert, objNormal);
    }
#endif // ENABLE_SKINNING

    mediump vec3 eyeToObj = uEyePos - objVert.xyz;
    highp float eyeToObjDist = length(eyeToObj);

    ObjectspaceV = objVert.xyz;

#ifdef ENABLE_PIXEL_LIGHTING
    ObjectspaceN = objNormal;
#else
    mediump vec3 L = uLightDir;
    mediump vec3 E = eyeToObj / eyeToObjDist;

    #ifdef BLINN_PHONG_SPECULAR
    mediump vec3 H = normalize(L + E);
    mediump float sf = max(0.0, dot(objNormal, H));
    #else
    mediump vec3 R = reflect(-L, objNormal);
    mediump float sf = max(0.0, dot(R, E));
    #endif

    sf = pow(sf, ColorSpecular.w);
    SpecularOut = vec4(ColorSpecular.rgb * sf, 0.0);
    
    mediump float df = max(0.0, dot(objNormal, L));
    DestinationColor = vec4(ColorAmbient + ColorDiffuse.rgb * df, ColorDiffuse.a);
#endif // ENABLE_PIXEL_LIGHTING
    
#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
    ComputeShadowPosition(objVert.xyz, objNormal);
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM
    
#ifdef ENABLE_FOG
    eyeToObj *= uInvObjScale;
    fogDist = length(eyeToObj);
#endif // ENABLE_FOG

    TextureCoordOut = inTexCoord;
    gl_Position = ModelviewProjection * objVert;
}
