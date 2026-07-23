#version 300 es
precision mediump float;
// TexturedLighting frag-shader: ES3 //////////

uniform lowp vec3 ColorAmbient;		// ambient RGB

in mediump vec2 TextureCoordOut;
uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0

uniform mediump vec3 uEyePos;
uniform mediump vec3 uInvObjScale;
in highp vec3 ObjectspaceV;    // Object space Vertex

#ifdef ENABLE_PIXEL_LIGHTING
// per pixel lighting: "glsl/Pixel.es3.frag" must append on this shader
lowp vec4 ShadeLit(in lowp vec4 texDiffuse);
lowp vec4 ShadeUnlit(in lowp vec4 texDiffuse);

#else
// per vertex lighting
in lowp vec4 SpecularOut;	// separate specular added
in lowp vec4 DestinationColor;

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

#ifdef ENABLE_FOG
lowp vec4 ApplyFog(in lowp vec4 texResult);
#endif // ENABLE_FOG

out vec4 fragColor;

void main(void)
{
	lowp vec4 texResult = texture(SamplerDiffuse, TextureCoordOut);	// tex-lookup
#ifdef ENABLE_TEXTURE0_BGRA	// iOS, macOS: CVPixelBuffer is BGRA, not RGBA
	texResult = texResult.bgra;
#endif // ENABLE_TEXTURE0_BGRA

#ifdef ENABLE_ALPHA_TEST
	if (texResult.a < 0.5)
		discard;
#endif // ENABLE_ALPHA_TEST
	
	////////// shadow map //////////
#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
	lowp float litFactor = ComputeShadowLitFactor();
	if (litFactor >= 1.0) {
		texResult = ShadeLit(texResult);
	} else if (litFactor <= 0.0) {
		texResult = ShadeUnlit(texResult);
	} else {
		texResult = mix(ShadeUnlit(texResult), ShadeLit(texResult), litFactor);
	}
#else // no shadow
    texResult = ShadeLit(texResult);
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM

#ifdef ENABLE_FOG
	texResult = ApplyFog(texResult);
#endif // ENABLE_FOG

	fragColor = texResult;
}
