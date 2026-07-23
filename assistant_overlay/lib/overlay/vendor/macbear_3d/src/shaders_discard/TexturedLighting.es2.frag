// TexturedLighting frag-shader: fog //////////
// NOTICE: "Pixel.es2.frag" must be added for per-pixel lighting

#ifndef ENABLE_PIXEL_LIGHTING

precision mediump float;

uniform lowp vec3 ColorAmbient;		// ambient RGB 

varying lowp vec4 SpecularOut;	// separate specular added
varying lowp vec4 DestinationColor;

// no pre-multiply alpha
// lit result by per-vertex
lowp vec4 ShadeLit(in lowp vec4 texDiffuse)
{
	lowp vec4 result = texDiffuse * DestinationColor;
	result.rgb += SpecularOut.rgb;
	return result;
}

lowp vec4 ShadeUnlit(in lowp vec4 texDiffuse)
{
	// unlit = ambient 
	return texDiffuse * vec4(ColorAmbient, DestinationColor.a);
}
#endif // ENABLE_PIXEL_LIGHTING

varying mediump vec2 TextureCoordOut;

uniform sampler2D SamplerDiffuse;		// GL_TEXTURE0

#ifdef ENABLE_FOG
varying mediump float FogDensity;		// fog density [0,1]
uniform lowp vec3 FogColor;
#endif // ENABLE_FOG

#ifdef ENABLE_SHADOW_MAP
varying highp vec4 LightcoordShadowmap;	// light-space coordinate-system
#endif // ENABLE_SHADOW_MAP

#ifdef ENABLE_SHADOW_CSM
varying highp vec4 LightcoordCSM[4];	// light-space coordinate-system
uniform highp vec4 DepthCSM;			// depth clip-plane
#endif // ENABLE_SHADOW_CSM

#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
uniform highp sampler2D SamplerShadowmap;	// GL_TEXTURE1
uniform highp vec2 ShadowmapSize;		// shadowmap resolution
uniform highp float NormalBias;			// normal bias (for shadow acne)
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM


void main(void)
{
	lowp vec4 texResult = texture2D(SamplerDiffuse, TextureCoordOut);	// tex-lookup
#ifdef ENABLE_ALPHA_TEST
	if (texResult.a < 0.5)
		discard;
#endif // ENABLE_ALPHA_TEST
	
	////////// shadow map //////////
#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
	#ifdef ENABLE_SHADOW_CSM
		highp vec4 LightcoordShadowmap = LightcoordCSM[3];
		if (gl_FragCoord.z < DepthCSM.x) {
			LightcoordShadowmap = LightcoordCSM[0];
		}
		else if (gl_FragCoord.z < DepthCSM.y) {
			LightcoordShadowmap = LightcoordCSM[1];
		}
		else if (gl_FragCoord.z < DepthCSM.z) {
			LightcoordShadowmap = LightcoordCSM[2];
		}
		else {
			LightcoordShadowmap = LightcoordCSM[3];
		}

		// gl_FragColor = vec4(vec3(gl_FragCoord.z), 1.0); // debug CSM
		// return;
	#endif // ENABLE_SHADOW_CSM
	
	if (LightcoordShadowmap.s < 0.0 || LightcoordShadowmap.t < 0.0 || LightcoordShadowmap.s > 1.0 || LightcoordShadowmap.t > 1.0) {
		texResult = ShadeLit(texResult);					// lit-area
	}
	else {

	////////// PCF //////////
	#ifdef ENABLE_PCF
		highp vec2 texelSize = vec2(1.0) / ShadowmapSize;
		highp vec4 depthPCF;	// depth-shadow by PCF
		depthPCF.x = texture2D(SamplerShadowmap, LightcoordShadowmap.st + vec2( 1.0,  0.5) * texelSize).r;
		depthPCF.y = texture2D(SamplerShadowmap, LightcoordShadowmap.st + vec2(-1.0, -0.5) * texelSize).r;
		depthPCF.z = texture2D(SamplerShadowmap, LightcoordShadowmap.st + vec2(-0.5,  1.0) * texelSize).r;
		depthPCF.w = texture2D(SamplerShadowmap, LightcoordShadowmap.st + vec2( 0.5, -1.0) * texelSize).r;
		
		depthPCF = step(vec4(LightcoordShadowmap.z - 0.0005), depthPCF);
		lowp float factorLit = dot(depthPCF, depthPCF) / 4.0;
		
		texResult = mix(ShadeUnlit(texResult), ShadeLit(texResult), factorLit);
		
	#else

		highp float depthShadow;
		depthShadow = texture2D(SamplerShadowmap, LightcoordShadowmap.st).r;
		//	depthShadow = texture2DProj(SamplerShadowmap, LightcoordShadowmap).r;	// palallel-projection, so w = 1 
		if (depthShadow < LightcoordShadowmap.z - 0.0005)
			texResult = ShadeUnlit(texResult);
		else
			texResult = ShadeLit(texResult);
	#endif // ENABLE_PCF

	// texResult = vec4(vec3(LightcoordShadowmap.z), 1.0);	// debug shadowmap
	}

#else
    texResult = ShadeLit(texResult);
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM

#ifdef ENABLE_FOG
	// Perform depth test and clamp the values
	lowp float fFogBlend = clamp(FogDensity + 1.0 - texResult.a, 0.0, 1.0);
	texResult.rgb = mix(texResult.rgb, FogColor, fFogBlend); 
#endif // ENABLE_FOG

	gl_FragColor = texResult;
}
