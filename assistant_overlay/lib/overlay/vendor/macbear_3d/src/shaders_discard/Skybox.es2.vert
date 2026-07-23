// Skybox vert-shader: via cubemap //////////
attribute highp vec3 inVertex;		// vertex-data

uniform lowp vec4 uColor;
varying lowp vec4 DestinationColor;
varying mediump vec3 TexCoordDirOut;
// eye-space for camera-viewer
uniform highp mat4 ModelviewProjection;

void main(void)
{
	highp vec4 objVert = vec4(inVertex, 1.0);

	TexCoordDirOut = objVert.xyz;
	DestinationColor = uColor;
	gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}
