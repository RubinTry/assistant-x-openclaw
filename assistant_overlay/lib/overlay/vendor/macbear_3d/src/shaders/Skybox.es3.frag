#version 300 es
precision mediump float;
// Skybox frag-shader ES3 //////////

in lowp vec4 DestinationColor;
in mediump vec3 TexCoordDirOut;
uniform samplerCube SamplerEnvironment; // cubemap texture
uniform mediump vec3 uParamPBR; // x: Metallic, y: Roughness, z: Mipmap-level
out vec4 fragColor;

void main(void)
{
    mediump float mipLevel = uParamPBR.y * uParamPBR.z; // Roughness * MaxMipLevel
    fragColor = textureLod(SamplerEnvironment, TexCoordDirOut, mipLevel) * DestinationColor;
}
