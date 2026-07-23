// Simple-lighting vert-shader //////////
// NOTICE: "Skinning.es2.vert" must be added before this file
#ifndef ENABLE_SKINNING
attribute highp vec3 inVertex;		// vertex-data
attribute mediump vec3 inNormal;
#endif // ENABLE_SKINNING

uniform lowp vec4 uColor;

// eye-space for camera-viewer
uniform mat4 ModelviewProjection;

// color combined by light and material
uniform lowp vec3 ColorAmbient;		// ambient RGB 
uniform lowp vec4 ColorDiffuse;		// diffuse RGBA
uniform mediump vec4 ColorSpecular;	// specular RGB, w: shininess

// object-space
uniform vec3 EyePosition;		// eye as camera origin
uniform vec3 LightPosition;		// parallel light

// shader variable: from vert to frag
varying lowp vec4 DestinationColor;

void main(void) {
	highp vec4 objVert = vec4(inVertex, 1.0);
	mediump vec3 objNormal = inNormal;

#ifdef ENABLE_SKINNING
	if (BoneCount > 0)
	{
		ComputeSkinningVertex(objVert, objNormal);
	}
#endif // ENABLE_SKINNING

	// object-space: normal, light-position, eye-position
	vec3 N = objNormal;
	vec3 L = LightPosition;							// parallel light source
	vec3 E = normalize(EyePosition - objVert.xyz);	// vertex to eye
	vec3 H = normalize(L + E);

	float df = max(0.0, dot(N, L));
	float sf = max(0.0, dot(N, H));
	sf = pow(sf, ColorSpecular.w);

	lowp vec3 AmbientDiffuseSpecular = (ColorAmbient + ColorDiffuse.rgb * df) + ColorSpecular.rgb * sf;

	DestinationColor = vec4(AmbientDiffuseSpecular, uColor.a);
	gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}
