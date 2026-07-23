#ifdef GL_EXT_shader_texture_lod
#extension GL_EXT_shader_texture_lod : enable
#endif

precision mediump float;

#define ENABLE_PIXEL_LIGHTING

// color combined by light and material
uniform lowp vec3 ColorAmbient;		// ambient RGB 
uniform lowp vec4 ColorDiffuse;		// diffuse RGBA
uniform mediump vec4 ColorSpecular;	// specular RGB, w: shininess

uniform mediump vec3 LightPosition;	// parallel light
varying mediump vec3 ObjectspaceN;
varying mediump vec3 ObjectspaceH;	// LightVector + EyeVector

mediump vec3 safe_normalize(mediump vec3 v) {
    mediump float len2 = max(dot(v, v), 1e-8);
    return v * inversesqrt(len2);
}

#ifdef ENABLE_PBR
varying mediump vec3 ObjectspaceV;
uniform mediump vec2 uParamPBR; // x: Metallic, y: Roughness

// Trowbridge-Reitz GGX
mediump float DistributionGGX(mediump vec3 N, mediump vec3 H, mediump float roughness) {
    mediump float a = roughness * roughness;
    mediump float a2 = a * a;
    mediump float NdotH = max(dot(N, H), 0.0);
    mediump float NdotH2 = NdotH * NdotH;

    mediump float num = a2;
    mediump float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = 3.14159265359 * denom * denom;

    return num / denom;
}

// Smith's method (Schlick-GGX)
mediump float GeometrySchlickGGX(mediump float NdotV, mediump float roughness) {
    mediump float r = (roughness + 1.0);
    mediump float k = (r * r) / 8.0;

    mediump float num = NdotV;
    mediump float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

mediump float GeometrySmith(mediump vec3 N, mediump vec3 V, mediump vec3 L, mediump float roughness) {
    mediump float NdotV = max(dot(N, V), 0.0);
    mediump float NdotL = max(dot(N, L), 0.0);
    mediump float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    mediump float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Schlick's approximation
mediump vec3 fresnelSchlick(mediump float cosTheta, mediump vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}
#endif // ENABLE_PBR

#ifdef ENABLE_IBL
uniform mediump mat4 Model;
uniform samplerCube SamplerEnvironment;

mediump vec3 ApplyIBL(mediump vec3 ambientDiffuse, mediump vec3 N, mediump vec3 V, mediump vec3 F) {
    // IBL: Sample environment map for ambient reflection
    mediump vec3 reflectDir = reflect(-V, N);
    reflectDir = normalize(mat3(Model) * reflectDir).xyz;
    // Swizzle to match skybox-cubemap orientation (rotXNeg90)
    mediump vec3 sampleDir;
    sampleDir.x = -reflectDir.x;
    sampleDir.y = reflectDir.z;
    sampleDir.z = -reflectDir.y;
    
    // Roughness based Mip-mapping for Specular IBL
#ifdef GL_EXT_shader_texture_lod
    // Assuming 7-8 mip levels for typical cubemap
    mediump float mipLevel = uParamPBR.y * 7.0; // Roughness
    mediump vec3 envColor = textureCubeLodEXT(SamplerEnvironment, sampleDir, mipLevel).rgb;
    envColor = pow(envColor, vec3(2.2));
#else
    mediump vec3 envColor = textureCube(SamplerEnvironment, sampleDir).rgb;
    envColor *= (1.0 - uParamPBR.y); // Roughness
    envColor = pow(envColor, vec3(2.2));
#endif
    
    // PBR weighting for ambient:
    // kS (specular) is the Fresnel F
    // kD (diffuse) reduction for energy conservation
    mediump vec3 kS = F;
    mediump vec3 kD = (vec3(1.0) - kS) * (1.0 - uParamPBR.x); // Metallic
    
    // IBL Specular reflection: attenuated by roughness
    mediump vec3 iblSpecular = envColor * kS;
    
    return kD * ambientDiffuse + iblSpecular;
}
#endif // ENABLE_IBL

// lit result by per-pixel: by lighting
lowp vec4 ShadeLit(in lowp vec4 texDiffuse)
{
	lowp vec4 result;
    mediump vec3 N = normalize(ObjectspaceN);
    mediump vec3 L = LightPosition;		// parallel light source

#ifdef ENABLE_PBR
    mediump vec3 V = safe_normalize(ObjectspaceV);
    mediump vec3 H = safe_normalize(V + L);

    // PBR calculations should be done in linear space
    mediump vec3 baseColor = pow(ColorDiffuse.rgb * texDiffuse.rgb, vec3(2.2));
    mediump float alpha = ColorDiffuse.a * texDiffuse.a;

    mediump vec3 F0 = vec3(0.04);
    F0 = mix(F0, baseColor, uParamPBR.x); // Metallic

    // Reflectance equation
    mediump float NDF = DistributionGGX(N, H, uParamPBR.y); // Roughness
    mediump float G = GeometrySmith(N, V, L, uParamPBR.y); // Roughness
    mediump vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    mediump vec3 kS = F;
    mediump vec3 kD = (vec3(1.0) - kS) * (1.0 - uParamPBR.x); // Metallic

    mediump vec3 numerator = NDF * G * F;
    mediump float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    mediump vec3 specular = numerator / denominator;

    mediump float NdotL = max(dot(N, L), 0.0);
    // Correct ambient: ColorAmbient already includes material diffuse, so just multiply by texDiffuse
    mediump vec3 ambient = pow(ColorAmbient, vec3(2.2)) * pow(texDiffuse.rgb, vec3(2.2));

    #ifdef ENABLE_IBL
    mediump vec3 Fibl = fresnelSchlick(max(dot(N, V), 0.0), F0);
    ambient = ApplyIBL(ambient, N, V, Fibl);
    #endif // ENABLE_IBL

    // Lit: ambient + (diffuse + specular)
    mediump vec3 color = ambient + (kD * baseColor + specular) * NdotL;

    // HDR tone mapping removed as we use LDR lights; only keep Gamma Correction
    color = pow(max(color, 0.0), vec3(1.0 / 2.2));

    result = vec4(color, alpha);
#else // ENABLE_PBR
    mediump vec3 H = safe_normalize(ObjectspaceH);

    mediump float df = max(0.0, dot(N, L));
    mediump float NdotH = max(0.0, dot(N, H));
    mediump float sf = pow(NdotH, ColorSpecular.w);

	#ifdef ENABLE_CARTOON
	// segment: 0___0.1___0.3___0.7___1
	// cartoon:   0    0.3  0.7    1
	df = dot(step(vec3(0.1,0.3,0.7), vec3(df)), vec3(0.3, 0.4, 0.3));
	sf = step(0.5, sf);
	#endif // ENABLE_CARTOON
	
	// lit = ambient + diffuse + specular * shininess
    result.a = texDiffuse.a * ColorDiffuse.a;
	result.rgb = texDiffuse.rgb * (ColorAmbient + ColorDiffuse.rgb * df);
    result.rgb = result.rgb + ColorSpecular.rgb * sf;

    return result;//vec4(1.0, 0.3, 0.0, 1.0);

#endif // ENABLE_PBR

	return result;
}

// unlit result by per-pixel: in shadow
lowp vec4 ShadeUnlit(in lowp vec4 texDiffuse)
{
	lowp vec4 result;

#ifdef ENABLE_PBR
    mediump vec3 N = safe_normalize(ObjectspaceN);
    mediump vec3 V = safe_normalize(ObjectspaceV);
    // baseColor not used for unlit ambient, but needed for alpha
    mediump float alpha = ColorDiffuse.a * texDiffuse.a;

    // Correct ambient: ColorAmbient already includes material diffuse, so just multiply by texDiffuse
    mediump vec3 ambient = pow(ColorAmbient, vec3(2.2)) * pow(texDiffuse.rgb, vec3(2.2));

    #ifdef ENABLE_IBL
    // PBR calculations for IBL
    mediump vec3 baseColor = pow(ColorDiffuse.rgb * texDiffuse.rgb, vec3(2.2));
    mediump vec3 F0 = vec3(0.04);
    F0 = mix(F0, baseColor, uParamPBR.x); // Metallic
    mediump vec3 F = fresnelSchlick(max(dot(N, V), 0.0), F0);

    ambient = ApplyIBL(ambient, N, V, F);
    #endif // ENABLE_IBL

    mediump vec3 color = ambient;
    color = pow(color, vec3(1.0 / 2.2));

    result = vec4(color, alpha);
#else
	// unlit = ambient 
	result = texDiffuse * vec4(ColorAmbient, ColorDiffuse.a);
#endif // ENABLE_PBR

	return result;
}