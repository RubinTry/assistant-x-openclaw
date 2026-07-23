// Generated file – do not edit.
// ignore: constant_identifier_names
const String Unlit_frag = r"""
#version 300 es
precision mediump float;
// Simple frag-shader ES3 //////////

in mediump vec2 TextureCoordOut;
in lowp vec4 DestinationColor;

#ifdef ENABLE_EXTERNAL_OES
uniform samplerExternalOES SamplerDiffuse;   // GL_TEXTURE0
#else
uniform sampler2D SamplerDiffuse;   // GL_TEXTURE0
#endif

out vec4 fragColor;

void main(void)
{
    lowp vec4 texResult = texture(SamplerDiffuse, TextureCoordOut);	// tex-lookup
#ifdef ENABLE_TEXTURE0_BGRA	// iOS, macOS: CVPixelBuffer is BGRA, not RGBA
	texResult = texResult.bgra;
#endif // ENABLE_TEXTURE0_BGRA

    fragColor = texResult * DestinationColor;
}

""";
