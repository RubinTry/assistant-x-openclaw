// Mirror vert-shader //////////
attribute highp vec3 inVertex;		// vertex-data
attribute lowp vec4 inColor;		// for mirror-color
// eye-space for camera-viewer
//uniform mat4 Projection;
uniform highp mat4 ModelviewProjection;

varying lowp vec4 DestinationColor;

void main(void)
{
	DestinationColor = inColor;
    gl_Position = ModelviewProjection * vec4(inVertex, 1.0);	// pre-compute Projection * Modelview
}
