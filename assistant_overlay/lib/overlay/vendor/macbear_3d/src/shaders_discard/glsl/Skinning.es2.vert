// Skinning vert-shader //////////
/*
 If the current vertex is affected by bones then the vertex position and
 normal will be transformed by the bone matrices. Each vertex wil have up 
 to 4 bone indices (inBoneIndex) and bone weights (inBoneWeights).
 
 The indices are used to index into the array of bone matrices 
 (BoneMatrixArray) to get the required bone matrix for transformation. The 
 amount of influence a particular bone has on a vertex is determined by the
 weights which should always total 1. So if a vertex is affected by 2 bones 
 the vertex position in world space is given by the following equation:
 
 position = (BoneMatrixArray[Index0] * inVertex) * Weight0 + 
 (BoneMatrixArray[Index1] * inVertex) * Weight1
 
 The same proceedure is applied to the normals but the translation part of 
 the transformation is ignored.
 
 After this the position is multiplied by the view and projection matrices 
 only as the bone matrices already contain the model transform for this 
 particular mesh. The two-step transformation is required because lighting 
 will not work properly in clip space.
 */
#define ENABLE_SKINNING
attribute highp vec3 inVertex;		// vertex-data

attribute mediump vec4 inBoneIndex;
attribute mediump vec4 inBoneWeight;
		  
// skinning mesh part: bone
uniform mediump int BoneCount;
uniform highp   mat4 BoneMatrixArray[32];
//uniform highp   mat3 BoneMatrixArrayIT[8];
/*
void ComputeSkinningVertex(out highp vec4 objVert, out mediump vec3 objNormal)
{
	highp vec4 srcVert = vec4(inVertex, 1.0);
	// On PowerVR SGX it is possible to index the components of a vector
	// with the [] operator. However this can cause trouble with PC
	// emulation on some hardware so we "rotate" the vectors instead.
	mediump ivec4 boneIndex = ivec4(inBoneIndex);
	mediump vec4 boneWeight = inBoneWeight;
	highp mat4 boneMatrix = BoneMatrixArray[boneIndex.x];
	highp mat3 normalMatrix = mat3(boneMatrix);//BoneMatrixArrayIT[boneIndex.x];

	objVert = boneMatrix * srcVert * boneWeight.x;
	objNormal = normalMatrix * inNormal * boneWeight.x;
	
	// PowerVR SGX supports uniforms in the for loop and nested conditionals.
	// For performance reasons, the code below should be like this:
	//	for (lowp int i = 1; i < BoneCount; ++i)
	//	{
	//		boneIndex = boneIndex.yzwx;
	//		boneWeight = boneWeight.yzwx;
	//	
	//		boneMatrix = BoneMatrixArray[boneIndex.x];
	//		normalMatrix = BoneMatrixArrayIT[boneIndex.x];
	//	
	//		if (boneWeight.x > 0.0)
	//		{
	//			objVert += boneMatrix * vec4(inVertex, 1.0) * boneWeight.x;
	//			objNormal += normalMatrix * inNormal * boneWeight.x;
	//		}
	//	}
	// However this code causes a severe crash on PCEmulation
	// in some ATI hardware due to a very limited loop support.
	// If you are targeting SGX, please, modify the code below.
	for (lowp int i = 1; i < BoneCount; ++i)
	{
		// "rotate" the vector components
		boneIndex = boneIndex.yzwx;
		boneWeight = boneWeight.yzwx;
		
		boneMatrix = BoneMatrixArray[boneIndex.x];
		normalMatrix = mat3(boneMatrix);//BoneMatrixArrayIT[boneIndex.x];
		
		objVert += boneMatrix * srcVert * boneWeight.x;
		objNormal += normalMatrix * inNormal * boneWeight.x;
	}
	objNormal = normalize(objNormal);
}
*/

// skinning vertex: discard for-loop, so extend to whole code
// (ps: iPad2 has some problem when using for-loop (4 times) in shader)
#ifdef ENABLE_NORMAL
attribute mediump vec3 inNormal;
void ComputeSkinningVertex(out highp vec4 objVert, out mediump vec3 objNormal)
#else
void ComputeSkinningVertex(out highp vec4 objVert)
#endif // ENABLE_NORMAL
{
	highp vec4 srcVert = vec4(inVertex, 1.0);
	// On PowerVR SGX it is possible to index the components of a vector
	// with the [] operator. However this can cause trouble with PC
	// emulation on some hardware so we "rotate" the vectors instead.
	mediump ivec4 boneIndex = ivec4(inBoneIndex + 0.5);

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
