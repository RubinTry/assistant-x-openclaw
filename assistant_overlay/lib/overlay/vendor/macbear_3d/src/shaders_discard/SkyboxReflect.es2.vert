// ES2.0: GLSL 100
// Skybox Reflect vert-shader: via cubemap //////////
// NOTICE 1: ENABLE_NORMAL must be defined first
// NOTICE 2: "Skinning.es2.vert" must be added for skinning
#ifndef ENABLE_SKINNING
attribute highp vec3 inVertex;		// vertex-data
attribute mediump vec3 inNormal;
#endif // ENABLE_SKINNING

// object space
uniform mediump vec3 EyePosition;			// eye as camera origin
uniform lowp vec4 uColor;

varying lowp vec4 DestinationColor;
varying mediump vec3 TexCoordDirOut;

// space transformation
uniform highp mat4 Model;
uniform highp mat4 ModelviewProjection;

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

	mediump vec3 eyeDir = normalize(objVert.xyz - EyePosition);	// by object-space
	mediump vec3 reflectDir = reflect(eyeDir, objNormal);		// by object-space
	reflectDir = mat3(Model) * reflectDir;						// by world-space

	// Swizzle to match skybox-cubemap orientation (rotXNeg90)
	TexCoordDirOut.x = -reflectDir.x;
	TexCoordDirOut.y = reflectDir.z;
	TexCoordDirOut.z = -reflectDir.y;

	DestinationColor = uColor;

    gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}
