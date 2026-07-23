#version 300 es
// Per-pixel lighting shader ES3 //////////
// must append to "TexturedLighting.es3.frag"

// color combined by light and material
uniform lowp vec4 ColorDiffuse;		// diffuse RGBA
uniform mediump vec4 ColorSpecular;	// specular RGB, w: shininess

uniform mediump vec3 uLightDir; // parallel light
in mediump vec3 ObjectspaceN;

mediump vec3 safe_normalize(mediump vec3 v) {
    mediump float len2 = max(dot(v, v), 1e-8);
    return v * inversesqrt(len2);
}

// multi-point-lights
lowp vec3 CalculateLighting(vec3 fragPos, vec3 N);

// View direction from surface to eye. Used by both Lit (for H = V+L) and Unlit (for IBL) paths.
mediump vec3 ComputeViewDir() {
    mediump vec3 ObjToEye = uEyePos - ObjectspaceV;
    return safe_normalize(ObjToEye);
}

#ifdef ENABLE_PBR
uniform mediump vec3 uParamPBR; // x: Metallic, y: Roughness, z: Mipmap-level

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

// ---- Shared PBR helpers (new: factor out logic duplicated between ShadeLit/ShadeUnlit) ----

// F0 reflectance at normal incidence, blended toward albedo by metallic.
mediump vec3 ComputeF0(mediump vec3 baseColor) {
    return mix(vec3(0.04), baseColor, uParamPBR.x); // Metallic
}

// ColorAmbient * texColor, converted to linear space. Identical term in both Lit/Unlit PBR paths.
mediump vec3 ComputeAmbientLinear(lowp vec3 texColor) {
    return pow(ColorAmbient, vec3(2.2)) * pow(texColor, vec3(2.2));
}

// Shared tail: gamma-correct linear color back to sRGB. Alpha is never part
// of the lighting math, so it's tracked separately and only combined at return.
mediump vec3 FinalizePBRColor(mediump vec3 linearColor) {
    return pow(max(linearColor, 0.0), vec3(1.0 / 2.2));
}
#endif // ENABLE_PBR

#ifdef ENABLE_IBL
uniform mediump mat4 Model;
uniform samplerCube SamplerEnvironment;

// kS: specular weight for this IBL sample (the Fresnel term computed by the caller).
mediump vec3 ApplyIBL(mediump vec3 ambientDiffuse, mediump vec3 N, mediump vec3 V, mediump vec3 kS) {
    // IBL: Sample environment map for ambient reflection
    mediump vec3 reflectDir = reflect(-V, N);
    reflectDir = normalize(mat3(Model) * reflectDir).xyz;
    // Swizzle to match skybox-cubemap orientation (rotXNeg90)
    mediump vec3 sampleDir;
    sampleDir.x = -reflectDir.x;
    sampleDir.y = reflectDir.z;
    sampleDir.z = -reflectDir.y;

    // Roughness based Mip-mapping for Specular IBL (ES3 native textureLod)
    mediump float mipLevel = uParamPBR.y * uParamPBR.z; // Roughness * MaxMipLevel
    mediump vec3 envColor = textureLod(SamplerEnvironment, sampleDir, mipLevel).rgb;
    envColor = pow(envColor, vec3(2.2));
    //--------------------
    // notice: comment block for align 'es2.frag' and 'es3.frag'
    // so we can use textureLod instead of textureCubeLodEXT
    // textureCubeLodEXT depend on 'GL_EXT_shader_texture_lod' extension
    // https://www.khronos.org/registry/OpenGL/extensions/EXT/EXT_shader_texture_lod.txt
    //--------------------

    // PBR weighting for ambient:
    // kD (diffuse) reduction for energy conservation
    mediump vec3 kD = (vec3(1.0) - kS) * (1.0 - uParamPBR.x); // Metallic

    // IBL Specular reflection: attenuated by roughness
    mediump vec3 iblSpecular = envColor * kS;

    return kD * ambientDiffuse + iblSpecular;
}
#endif // ENABLE_IBL

// lit result by per-pixel: by lighting
lowp vec4 ShadeLit(in lowp vec4 texDiffuse)
{
	lowp vec3 resultColor;
    mediump vec3 N = safe_normalize(ObjectspaceN);
    mediump vec3 L = uLightDir;		// parallel light source
    mediump vec3 V = ComputeViewDir();
    mediump vec3 H = safe_normalize(V + L);
    mediump vec4 diffuse = ColorDiffuse * texDiffuse;

#ifdef ENABLE_PBR
    // PBR calculations should be done in linear space
    mediump vec3 baseColor = pow(diffuse.rgb, vec3(2.2));

    mediump vec3 F0 = ComputeF0(baseColor);

    // Reflectance equation
    mediump float NDF = DistributionGGX(N, H, uParamPBR.y); // Roughness
    mediump float G = GeometrySmith(N, V, L, uParamPBR.y); // Roughness
    mediump vec3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    mediump vec3 kD = (vec3(1.0) - F) * (1.0 - uParamPBR.x); // Metallic

    mediump vec3 numerator = NDF * G * F;
    mediump float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    mediump vec3 specular = numerator / denominator;

    mediump float NdotL = max(dot(N, L), 0.0);
    mediump vec3 ambient = ComputeAmbientLinear(texDiffuse.rgb);

    #ifdef ENABLE_IBL
    mediump vec3 Fibl = fresnelSchlick(max(dot(N, V), 0.0), F0);
    ambient = ApplyIBL(ambient, N, V, Fibl);
    #endif // ENABLE_IBL

    // Lit: ambient + (diffuse + specular)
    mediump vec3 color = ambient + (kD * baseColor + specular) * NdotL;

    // HDR tone mapping removed as we use LDR lights; only keep Gamma Correction
    resultColor = FinalizePBRColor(color);
#else // ENABLE_PBR
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
	resultColor = texDiffuse.rgb * (ColorAmbient + ColorDiffuse.rgb * df);
    resultColor = resultColor + ColorSpecular.rgb * sf;
#endif // ENABLE_PBR

    resultColor += CalculateLighting(ObjectspaceV, ObjectspaceN) * diffuse.rgb;

	return vec4(resultColor, diffuse.a);
}

// unlit result by per-pixel: in shadow
lowp vec4 ShadeUnlit(in lowp vec4 texDiffuse)
{
	lowp vec3 resultColor;
    mediump vec4 diffuse = ColorDiffuse * texDiffuse;

#ifdef ENABLE_PBR
    mediump vec3 N = safe_normalize(ObjectspaceN);
    mediump vec3 V = ComputeViewDir();

    mediump vec3 ambient = ComputeAmbientLinear(texDiffuse.rgb);

    #ifdef ENABLE_IBL
    // PBR calculations for IBL
    mediump vec3 baseColor = pow(diffuse.rgb, vec3(2.2));
    mediump vec3 F0 = ComputeF0(baseColor);
    mediump vec3 F = fresnelSchlick(max(dot(N, V), 0.0), F0);

    ambient = ApplyIBL(ambient, N, V, F);
    #endif // ENABLE_IBL

    resultColor = FinalizePBRColor(ambient);
#else
	// unlit = ambient
	resultColor = texDiffuse.rgb * ColorAmbient;
#endif // ENABLE_PBR

    resultColor += CalculateLighting(ObjectspaceV, ObjectspaceN) * diffuse.rgb;

	return vec4(resultColor, diffuse.a);
}
