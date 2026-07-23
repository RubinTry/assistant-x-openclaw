// TexturedLighting vert-shader: fog //////////
// NOTICE 1: ENABLE_NORMAL must be defined first
// NOTICE 2: "Skinning.es2.vert" must be added for skinning
#ifndef ENABLE_SKINNING
attribute highp vec3 inVertex;		// vertex-data
attribute mediump vec3 inNormal;
#endif // ENABLE_SKINNING

attribute mediump vec2 inTexCoord;
//attribute mediump vec4 inColor;		// as diffuse-ambient material
uniform lowp vec4 uColor;

#ifdef ENABLE_PIXEL_LIGHTING
varying mediump vec3 ObjectspaceN;	// Object space Normal
varying mediump vec3 ObjectspaceH;	// LightVector + EyeVector
#ifdef ENABLE_PBR
varying mediump vec3 ObjectspaceV;	// Eye vector (V)
#endif // ENABLE_PBR
#else // ENABLE_PIXEL_LIGHTING
// color combined by light and material
uniform lowp vec4 ColorDiffuse;		// diffuse RGBA
uniform mediump vec4 ColorSpecular;	// specular RGB, w: shininess
varying lowp vec4 SpecularOut;		// separate specular added
#endif // ENABLE_PIXEL_LIGHTING

uniform lowp vec3 ColorAmbient;		// ambient RGB 

// object space
uniform mediump vec3 EyePosition;	// eye as camera origin
uniform mediump vec3 LightPosition;	// parallel light

// shader variable: from vert to frag
varying lowp vec4 DestinationColor;
varying mediump vec2 TextureCoordOut;

// eye-space for camera-viewer
//uniform mat4 Projection;
uniform mat4 ModelviewProjection;

#ifdef ENABLE_SHADOW_MAP
// light-space matrix for shadowmap in texture-space
uniform mat4 MatrixShadowmap;
varying highp vec4 LightcoordShadowmap;	// light-space coordinate-system
#endif // ENABLE_SHADOW_MAP

#ifdef ENABLE_SHADOW_CSM
// light-space matrix for shadowmap in texture-space
uniform mat4 MatrixCSM[4];
varying highp vec4 LightcoordCSM[4];	// light-space coordinate-system
#endif // ENABLE_SHADOW_CSM

#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
uniform highp float NormalBias;			// normal bias (for shadow acne)
#endif

#ifdef ENABLE_FOG
// fog depth on water
uniform mediump vec4 FogPlane;		// fog-plane in object-space
uniform mediump float FogDepth;		// max depth of fog
varying mediump float FogDensity;	// fog density [0,1]
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

	// object-space: normal, light-position, eye-position
	mediump vec3 L = LightPosition;							// parallel light source
	mediump vec3 E = normalize(EyePosition - objVert.xyz);	// vertex to eye
#ifdef ENABLE_PIXEL_LIGHTING
	ObjectspaceH = normalize(L + E);
	#ifdef ENABLE_PBR
	ObjectspaceV = E;
	#endif // ENABLE_PBR
	
	ObjectspaceN = objNormal;
#else // ENABLE_PIXEL_LIGHTING
	#ifdef BLINN_PHONG_SPECULAR
	mediump vec3 H = normalize(L + E);
	mediump float sf = max(0.0, dot(objNormal, H));
	#else // regular Phong shader
	mediump vec3 R = reflect(-L, objNormal);	// 2N(N.L) - L
	mediump float sf = max(0.0, dot(R, E));
	#endif // BLINN_PHONG_SPECULAR

	sf = pow(sf, ColorSpecular.w);
	SpecularOut = vec4(ColorSpecular.rgb * sf, 0.0);
	
	mediump float df = max(0.0, dot(objNormal, L));
	DestinationColor = vec4(ColorAmbient + ColorDiffuse.rgb * df, ColorDiffuse.a);
#endif // ENABLE_PIXEL_LIGHTING
	
	
#ifdef ENABLE_SHADOW_MAP
	vec3 biasedVertMap = objVert.xyz + objNormal * NormalBias;
	LightcoordShadowmap = MatrixShadowmap * vec4(biasedVertMap, 1.0);
#endif // ENABLE_SHADOW_MAP
	
#ifdef ENABLE_SHADOW_CSM
	// cascaded shadowmap
	vec3 biasedVertCSM = objVert.xyz + objNormal * NormalBias;
	LightcoordCSM[0] = MatrixCSM[0] * vec4(biasedVertCSM, 1.0);
	LightcoordCSM[1] = MatrixCSM[1] * vec4(biasedVertCSM, 1.0);
	LightcoordCSM[2] = MatrixCSM[2] * vec4(biasedVertCSM, 1.0);
	LightcoordCSM[3] = MatrixCSM[3] * vec4(biasedVertCSM, 1.0);
#endif // ENABLE_SHADOW_CSM

#ifdef ENABLE_FOG
	// for fog density
	mediump float DepthInFog = dot(FogPlane.xyz, objVert.xyz) + FogPlane.w;
	FogDensity = DepthInFog / FogDepth;
#endif // ENABLE_FOG
	
	TextureCoordOut = inTexCoord;
    gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}
