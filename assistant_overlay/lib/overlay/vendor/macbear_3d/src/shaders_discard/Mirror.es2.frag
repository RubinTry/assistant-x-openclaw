// Mirror frag-shader //////////
varying lowp vec4 DestinationColor;

uniform sampler2D SamplerDiffuse;	// GL_TEXTURE0
uniform mediump vec4 CameraViewport;		// xyzw for (x,y,width,height)
		  
void main(void)
{
	mediump vec2 vTexCoord = (gl_FragCoord.xy - CameraViewport.xy) / CameraViewport.zw;
    gl_FragColor = texture2D(SamplerDiffuse, vTexCoord) * DestinationColor;
}
