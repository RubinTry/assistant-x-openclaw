// Generated file – do not edit.
// ignore: constant_identifier_names
const String Water_frag = r"""
#version 300 es
precision mediump float;
// Water frag-shader ES3 //////////

// water distortion (noise effect)
in mediump vec2 BumpCoord0;
in mediump vec2 BumpCoord1;
in highp vec3 eyeToObj;		// interpolate from vert to frag: must be highp in iPad3 
in highp float eyeToObjDist;
in highp vec3 ObjectspaceV;    // Object space Vertex
uniform mediump vec3 uInvObjScale;

uniform mediump float WaveDistortion;

uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0: diffuse as reflection
uniform sampler2D NormalTex;		// GL_TEXTURE1: normalmap (Normal map uses z-axis major)
uniform sampler2D RefractionTex;	// GL_TEXTURE2: refraction
uniform mediump vec4 CameraViewport; // xyzw for (x,y,width,height)

// uniform lowp vec4 uColor;

// shade lit/unlit functions
lowp vec4 ShadeLit(in lowp vec4 texDiffuse)
{
	return texDiffuse;
}

lowp vec4 ShadeUnlit(in lowp vec4 texDiffuse)
{
	return vec4(texDiffuse.rgb * 0.7, 1.0);
}

// output color
out vec4 fragColor;

// blend reflection and refraction
lowp vec4 BlendReflectionRefraction(in lowp vec3 vAccumulatedNormal, in lowp vec3 eyeToObjNormal)
{
	// Calculate the Fresnel term to determine amount of reflection for each fragment
	mediump float fresnel = clamp(dot(eyeToObjNormal, vAccumulatedNormal), 0.0, 1.0);
	fresnel = 1.0 - fresnel;
	fresnel = pow(fresnel, 5.0);
	fresnel = (0.9 * fresnel) + 0.1;	// R(0)-1 = ~0.98 , R(0)= ~0.02
	
	// Calculate the tex coords of the fragment (using it's position on the screen), normal map is z-axis major.
	mediump vec2 vTexCoord = (gl_FragCoord.xy - CameraViewport.xy) / CameraViewport.zw;

	// Divide by eyeToObjDist to scale down the distortion
	// of fragments based on their distance from the camera 
	vTexCoord.xy -= vAccumulatedNormal.xy * (WaveDistortion / eyeToObjDist);

	// reflection, refraction
	lowp vec4 ReflectionColor = texture(SamplerDiffuse, vTexCoord);
	lowp vec4 RefractionColor = texture(RefractionTex, vTexCoord);
	// Blend reflection and refraction
	lowp vec4 result;
	result = mix(RefractionColor, ReflectionColor, fresnel);
//	result = mix(ReflectionColor, RefractionColor, 0.4);	// Constant mix
//	result = RefractionColor;			// ReflectionColor, RefractionColor only
	return result;
}

#ifdef ENABLE_WATER_SPECULAR
// tangent-space by light
uniform lowp vec3 LightDiffuse;		// diffuse of light
uniform mediump vec3 uLightDir;		// parallel light
#endif // ENABLE_WATER_SPECULAR

#ifdef ENABLE_FOG
lowp vec4 ApplyFog(in lowp vec4 texResult);
#endif // ENABLE_FOG

// multi-point-lights
lowp vec3 CalculateLighting(vec3 fragPos, vec3 N);

void main(void)
{
	// Use normalisation cube map instead of normalize() - See section 3.3.1 of white paper for more info
	// Macbear note: no need at new hardward
	// - See section 6.5 of PowerVR SGX.OpenGL ES 2.0 Application Development Recommendations
	// lowp vec3 eyeToObjNormal = normalize(eyeToObj);
	lowp vec3 eyeToObjNormal = eyeToObj / eyeToObjDist; // as normalize: increase little FPS, but seem lost precision
	
	// When distortion is enabled, use the normal map to calculate perturbation
	// Same as * 2.0 - 1.0
	lowp vec3 vAccumulatedNormal = texture(NormalTex, BumpCoord0).rgb + texture(NormalTex, BumpCoord1).rgb - 1.0;

	// blend reflection and refraction
	lowp vec4 resultColor;
	resultColor = BlendReflectionRefraction(vAccumulatedNormal, eyeToObjNormal);

#ifdef ENABLE_WATER_SPECULAR
	// specular part:
	mediump vec3 H = normalize(eyeToObjNormal + uLightDir);
	mediump float sf = max(0.0, dot(H, vAccumulatedNormal));
//	mediump float sf = clamp(dot(H, vAccumulatedNormal), 0.0, 1.0);
	sf = pow(sf, 120.0);
	
	lowp float fTemp = sf;
//	resultColor = vec4(LightDiffuse * fTemp, 1.0);		// for debug purpose
	resultColor = vec4(resultColor.rgb + LightDiffuse * fTemp, 1.0);
	// resultColor = vec4(uColor, 1);
#endif // ENABLE_WATER_SPECULAR

#if defined(ENABLE_SHADOW_MAP) || defined(ENABLE_SHADOW_CSM)
	lowp float litFactor = ComputeShadowLitFactor();
	if (litFactor >= 1.0) {
		resultColor = ShadeLit(resultColor);
	} else if (litFactor <= 0.0) {
		resultColor = ShadeUnlit(resultColor);
	} else {
		resultColor = mix(ShadeUnlit(resultColor), ShadeLit(resultColor), litFactor);
	}
#endif // ENABLE_SHADOW_MAP or ENABLE_SHADOW_CSM

	resultColor.rgb += CalculateLighting(ObjectspaceV, vAccumulatedNormal) * 0.3;

#ifdef ENABLE_FOG
	resultColor = ApplyFog(resultColor);
#endif // ENABLE_FOG

	fragColor = resultColor;
}

""";
