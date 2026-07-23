// Generated file – do not edit.
// ignore: constant_identifier_names
const String SkinningVS_glsl = r"""
#version 300 es
// Skinning vert-shader ES3 //////////
// must insert before vertex shader

#define ENABLE_SKINNING

layout(location = 0) in highp vec3 inVertex;
layout(location = 4) in mediump vec4 inBoneIndex; // Back to vec4 for buffer compatibility
layout(location = 5) in mediump vec4 inBoneWeight;

// skinning mesh part: bone
uniform mediump int BoneCount;
uniform highp mat4 BoneMatrixArray[32];

#ifdef ENABLE_NORMAL
layout(location = 2) in mediump vec3 inNormal;
void ComputeSkinningVertex(out highp vec4 objVert, out mediump vec3 objNormal)
#else
void ComputeSkinningVertex(out highp vec4 objVert)
#endif // ENABLE_NORMAL
{
    highp vec4 srcVert = vec4(inVertex, 1.0);
    
    // Cast vec4 to ivec4 for lookup
    ivec4 boneIndex = ivec4(inBoneIndex + 0.5);

    objVert = BoneMatrixArray[boneIndex.x] * srcVert * inBoneWeight.x;
#ifdef ENABLE_NORMAL
    objNormal = mat3(BoneMatrixArray[boneIndex.x]) * inNormal * inBoneWeight.x;
#endif // ENABLE_NORMAL

    if (BoneCount > 1)
    {
        objVert += BoneMatrixArray[boneIndex.y] * srcVert * inBoneWeight.y;
#ifdef ENABLE_NORMAL
        objNormal += mat3(BoneMatrixArray[boneIndex.y]) * inNormal * inBoneWeight.y;
#endif // ENABLE_NORMAL
        if (BoneCount > 2)
        {
            objVert += BoneMatrixArray[boneIndex.z] * srcVert * inBoneWeight.z;
#ifdef ENABLE_NORMAL
            objNormal += mat3(BoneMatrixArray[boneIndex.z]) * inNormal * inBoneWeight.z;
#endif // ENABLE_NORMAL
            if (BoneCount > 3)
            {
                objVert += BoneMatrixArray[boneIndex.w] * srcVert * inBoneWeight.w;
#ifdef ENABLE_NORMAL
                objNormal += mat3(BoneMatrixArray[boneIndex.w]) * inNormal * inBoneWeight.w;
#endif // ENABLE_NORMAL
            }
        }
    }
#ifdef ENABLE_NORMAL
    objNormal = normalize(objNormal);
#endif // ENABLE_NORMAL
}

""";
