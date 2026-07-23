// Generated file – do not edit.
// ignore: constant_identifier_names
const String Water_vert = r"""
#version 300 es
// Water vert-shader ES3 //////////
#ifndef ENABLE_SKINNING
layout(location = 0) in highp vec3 inVertex;		// vertex-data
#endif // ENABLE_SKINNING

// layout(location = 1) in lowp vec4 inColor;		// for water-color as fog in water
layout(location = 3) in mediump vec2 inTexCoord;

uniform lowp vec4 uColor;

// eye-space for camera-viewer
uniform highp mat4 ModelviewProjection;
// object-space (same as world-space here)
uniform mediump vec3 uEyePos;	// eye as camera origin

uniform mediump vec4 BumpTranslateScale0;	// xy: translate, zw: scale
uniform mediump vec4 BumpTranslateScale1;	// xy: translate, zw: scale

// tangent-space by plane
uniform lowp vec3 AxisTangent;		// as X-axis
uniform lowp vec3 AxisBinormal;		// as Y-axis
uniform lowp vec3 AxisNormal;		// as Z-axis

// shader variable: from vert to frag
out mediump vec2 BumpCoord0;
out mediump vec2 BumpCoord1;
out highp vec3 eyeToObj;		// interpolate from vert to frag: must be highp in iPad3 
out highp float eyeToObjDist;
out highp vec3 ObjectspaceV;    // Object space Vertex

out lowp vec4 DestinationColor;

#ifdef ENABLE_FOG
out highp float fogDist;   // distance: eye to obj-vertex
#endif // ENABLE_FOG

void main(void)
{
	DestinationColor = uColor;
	
	highp vec4 objVert = vec4(inVertex, 1.0);
#ifdef ENABLE_SKINNING
	if (BoneCount > 0)
	{
		ComputeSkinningVertex(objVert);
	}
#endif // ENABLE_SKINNING

#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
    ComputeShadowPosition(objVert.xyz, AxisNormal);
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM

    gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
	
	// Scale and translate texture coordinates used to sample the normal map - section 2.2 of white paper
	BumpCoord0 = (inTexCoord * BumpTranslateScale0.zw) + BumpTranslateScale0.xy;
	BumpCoord1 = (inTexCoord * BumpTranslateScale1.zw) + BumpTranslateScale1.xy;
	
	// The water to eye vector is used to calculate the Fresnel term
	// and to fade out perturbations based on distance from the viewer
	eyeToObj = uEyePos - objVert.xyz;
	eyeToObjDist = length(eyeToObj);
	
	ObjectspaceV = objVert.xyz;

	// tangent-space
	eyeToObj = vec3(dot(AxisTangent, eyeToObj), dot(AxisBinormal, eyeToObj), dot(AxisNormal, eyeToObj));

#ifdef ENABLE_FOG
    fogDist = eyeToObjDist;
#endif // ENABLE_FOG
}

""";
