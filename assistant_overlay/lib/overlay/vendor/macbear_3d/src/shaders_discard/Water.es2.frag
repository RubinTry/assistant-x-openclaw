// Water frag-shader //////////
// water distortion (noise effect)
varying mediump vec2 BumpCoord0;
varying mediump vec2 BumpCoord1;
varying highp vec3 WaterToEye;		// interpolate from vert to frag: must be highp in iPad3 
varying highp float WaterToEyeLength;

uniform mediump float	WaveDistortion;

uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0: diffuse as reflection
uniform sampler2D NormalTex;		// GL_TEXTURE1: normalmap (Normal map uses z-axis major)
uniform sampler2D RefractionTex;	// GL_TEXTURE2: refraction
uniform mediump vec4 CameraViewport;		// xyzw for (x,y,width,height)

// blend reflection and refraction
void BlendReflectionRefraction(out lowp vec4 ResultColor, in lowp vec3 vAccumulatedNormal, in lowp vec3 WaterToEyeNormal)
{
	// Calculate the Fresnel term to determine amount of reflection for each fragment
	mediump float fAirWaterFresnel = clamp(dot(WaterToEyeNormal,vAccumulatedNormal),0.0,1.0);
	fAirWaterFresnel = 1.0 - fAirWaterFresnel;
	fAirWaterFresnel = pow(fAirWaterFresnel, 5.0);
	fAirWaterFresnel = (0.9 * fAirWaterFresnel) + 0.1;	// R(0)-1 = ~0.98 , R(0)= ~0.02
	lowp float fTemp = fAirWaterFresnel;
	
	// Calculate the tex coords of the fragment (using it's position on the screen), normal map is z-axis major.
	mediump vec2 vTexCoord = (gl_FragCoord.xy - CameraViewport.xy) / CameraViewport.zw;

	// Divide by WaterToEyeLength to scale down the distortion
	// of fragments based on their distance from the camera 
	vTexCoord.xy -= vAccumulatedNormal.xy * (WaveDistortion / WaterToEyeLength);

	// reflection, refraction
	lowp vec4 ReflectionColor = texture2D(SamplerDiffuse, vTexCoord);
	lowp vec4 RefractionColor = texture2D(RefractionTex, vTexCoord);
	// Blend reflection and refraction
	ResultColor = mix(RefractionColor, ReflectionColor, fTemp);

//	ResultColor = mix(ReflectionColor, RefractionColor, 0.4);	// Constant mix
//	ResultColor = RefractionColor;			// ReflectionColor, RefractionColor only
}

#ifdef ENABLE_WATER_SPECULAR
// tangent-space by light
uniform lowp vec3 LightDiffuse;		// diffuse of light
uniform mediump vec3 LightPosition;	// parallel light
#endif // ENABLE_WATER_SPECULAR
		  
void main(void)
{
	// Use normalisation cube map instead of normalize() - See section 3.3.1 of white paper for more info
	// Macbear note: no need at new hardward
	// - See section 6.5 of PowerVR SGX.OpenGL ES 2.0 Application Development Recommendations
	lowp vec3 WaterToEyeNormal = normalize(WaterToEye);
//	lowp vec3 WaterToEyeNormal = WaterToEye / WaterToEyeLength;		// as normalize: increase little FPS, but seem lost precision
	
	// When distortion is enabled, use the normal map to calculate perturbation
	// Same as * 2.0 - 1.0
	lowp vec3 vAccumulatedNormal = texture2D(NormalTex, BumpCoord0).rgb + texture2D(NormalTex, BumpCoord1).rgb - 1.0;

	// blend reflection and refraction
	lowp vec4 BlendResultColor;
	BlendReflectionRefraction(BlendResultColor, vAccumulatedNormal, WaterToEyeNormal);

#ifdef ENABLE_WATER_SPECULAR
	// specular part:
	mediump vec3 WaterHalf = normalize(WaterToEyeNormal + LightPosition);
	mediump float sf = max(0.0, dot(WaterHalf, vAccumulatedNormal));
//	mediump float sf = clamp(dot(WaterHalf, vAccumulatedNormal), 0.0, 1.0);
	sf = pow(sf, 120.0);
	
	lowp float fTemp = sf;
//	BlendResultColor = vec4(LightDiffuse * fTemp, 1.0);		// for debug purpose
	BlendResultColor = vec4(BlendResultColor.rgb + LightDiffuse * fTemp, 1.0);
#endif // ENABLE_WATER_SPECULAR
	
	gl_FragColor = BlendResultColor;
}
