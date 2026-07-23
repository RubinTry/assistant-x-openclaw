// Generated file – do not edit.
// ignore: constant_identifier_names
const String Mirror_frag = r"""
#version 300 es
precision mediump float;
// Mirror frag-shader //////////

in lowp vec4 DestinationColor;

uniform mediump vec3 uParamPBR; // x: Metallic, y: Roughness, z: Mipmap-level
uniform sampler2D SamplerDiffuse; // GL_TEXTURE0
uniform mediump vec4 CameraViewport; // xyzw for (x,y,width,height)
out vec4 fragColor;

void main(void)
{
    // Roughness based Mip-mapping (ES3 native textureLod)
    mediump float mipLevel = uParamPBR.y * uParamPBR.z; // Roughness * MaxMipLevel
	mediump vec2 vTexCoord = (gl_FragCoord.xy - CameraViewport.xy) / CameraViewport.zw;

    fragColor = textureLod(SamplerDiffuse, vTexCoord, mipLevel) * DestinationColor;
}

""";
