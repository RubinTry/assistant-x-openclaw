#version 300 es
precision mediump float;
// Rect frag-shader ES3 //////////

in mediump vec2 TextureCoordOut;
in lowp vec4 DestinationColor;

uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0
out vec4 fragColor;

void main(void)
{
    fragColor = texture(SamplerDiffuse, TextureCoordOut) * DestinationColor;
}
