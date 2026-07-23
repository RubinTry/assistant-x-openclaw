// Generated file – do not edit.
// ignore: constant_identifier_names
const String SkyboxReflect_vert = r"""
#version 300 es
// Skybox Reflect vert-shader ES3 //////////
// NOTICE 1: ENABLE_NORMAL must be defined first
// NOTICE 2: "Skinning.es3.vert" must be added for skinning
#ifndef ENABLE_SKINNING
layout(location = 0) in highp vec3 inVertex;		// vertex-data
layout(location = 2) in mediump vec3 inNormal;
#endif // ENABLE_SKINNING

// object space
uniform mediump vec3 uEyePos;	// eye as camera origin
uniform lowp vec4 uColor;

out lowp vec4 DestinationColor;
out mediump vec3 TexCoordDirOut;

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

	mediump vec3 eyeDir = normalize(objVert.xyz - uEyePos);	// by object-space
	mediump vec3 reflectDir = reflect(eyeDir, objNormal);		// by object-space
	reflectDir = mat3(Model) * reflectDir;						// by world-space

	// Swizzle to match skybox-cubemap orientation (rotXNeg90)
	TexCoordDirOut.x = -reflectDir.x;
	TexCoordDirOut.y = reflectDir.z;
	TexCoordDirOut.z = -reflectDir.y;

	DestinationColor = uColor;

    gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}

""";
