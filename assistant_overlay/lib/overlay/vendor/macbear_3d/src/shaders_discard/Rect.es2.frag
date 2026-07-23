// Rect frag-shader //////////
varying mediump vec2 TextureCoordOut;
varying lowp vec4 DestinationColor;

uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0

void main(void)
{
    gl_FragColor = texture2D(SamplerDiffuse, TextureCoordOut) * DestinationColor;
//    gl_FragColor = vec4(1,1,1,1);
}
