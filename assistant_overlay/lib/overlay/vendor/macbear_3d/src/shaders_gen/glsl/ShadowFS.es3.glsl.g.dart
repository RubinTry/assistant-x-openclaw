// Generated file – do not edit.
// ignore: constant_identifier_names
const String ShadowFS_glsl = r"""
#version 300 es
// Shadow frag-shader: ES3 //////////
// must insert before fragment shader

// -------------------------
// Shadow with PCF
// -------------------------
uniform highp sampler2DShadow SamplerShadowmap; // GL_TEXTURE3
uniform highp vec2 ShadowmapSize;               // shadowmap resolution
uniform highp float NormalBias;                 // normal bias (for shadow acne)

// compute shadow with PCF
lowp float ComputeShadowPCF(in highp vec4 lightCoord)
{
    lowp float factorLit = 0.0;
    highp float refZ = lightCoord.z - 0.0005; // apply bias

////////// PCF //////////
#ifdef ENABLE_PCF
    highp vec2 texelSize = vec2(1.0) / ShadowmapSize;
    lowp vec4 factor;	// shadow factor by hardware-PCF
    factor.x = texture(SamplerShadowmap, vec3(lightCoord.st + vec2( 1.0,  0.5) * texelSize, refZ));
    factor.y = texture(SamplerShadowmap, vec3(lightCoord.st + vec2(-1.0, -0.5) * texelSize, refZ));
    factor.z = texture(SamplerShadowmap, vec3(lightCoord.st + vec2(-0.5,  1.0) * texelSize, refZ));
    factor.w = texture(SamplerShadowmap, vec3(lightCoord.st + vec2( 0.5, -1.0) * texelSize, refZ));
    
    factorLit = dot(factor, vec4(1.0)) / 4.0;
#elif defined(ENABLE_PCF_3x3) || defined(ENABLE_PCF_5x5)
    highp vec2 texelSize = vec2(1.0) / ShadowmapSize;
    #if defined(ENABLE_PCF_5x5)
        const float range = 2.0;
        const float samples = 25.0;
    #else
        const float range = 1.0;
        const float samples = 9.0;
    #endif

    for (float y = -range; y <= range; y += 1.0) {
        for (float x = -range; x <= range; x += 1.0) {
            factorLit += texture(SamplerShadowmap, vec3(lightCoord.st + vec2(x, y) * texelSize, refZ));
        }
    }
    factorLit /= samples;
#else // no PCF
    factorLit = texture(SamplerShadowmap, vec3(lightCoord.st, refZ));
#endif // ENABLE_PCF
    return factorLit;
}
// -------------------------
// Shadow Map or CSM
// -------------------------
#ifdef ENABLE_SHADOW_CSM
in highp vec4 LightcoordCSM[4];		// light-space coordinate-system
uniform highp vec4 DepthCSM;		// depth clip-plane
#else // ENABLE_SHADOW_MAP
in highp vec4 LightcoordShadowmap;	// light-space coordinate-system
#endif // ENABLE_SHADOW_CSM

// compute litFactor with shadow
lowp float ComputeShadowLitFactor()
{
#ifdef ENABLE_SHADOW_CSM
	highp vec4 lightCoord = LightcoordCSM[3];
	if (gl_FragCoord.z < DepthCSM.x) {
		lightCoord = LightcoordCSM[0];
	}
	else if (gl_FragCoord.z < DepthCSM.y) {
		lightCoord = LightcoordCSM[1];
	}
	else if (gl_FragCoord.z < DepthCSM.z) {
		lightCoord = LightcoordCSM[2];
	}
#else // ENABLE_SHADOW_MAP
	highp vec4 lightCoord = LightcoordShadowmap;
#endif // ENABLE_SHADOW_CSM

	if (lightCoord.s < 0.0 || lightCoord.t < 0.0 || lightCoord.s > 1.0 || lightCoord.t > 1.0) {
		return 1.0; // lit area
	} else {
		return ComputeShadowPCF(lightCoord); // shadow area with PCF
	}
}

""";
