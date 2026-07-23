#version 300 es
// Rect vert-shader ES3 //////////
layout(location = 0) in highp vec3 inVertex;		// vertex-data
layout(location = 3) in mediump vec2 inTexCoord;

uniform lowp vec4 uColor;

// eye-space for camera-viewer
uniform highp mat4 Projection;		// ortho-matrix
uniform highp mat4 Model;			// model-matrix (by screen-object)

uniform highp mat3 uTexMatrix;		// texture-matrix (uv mapping)
out mediump vec2 TextureCoordOut;
out lowp vec4 DestinationColor;

void main(void)
{
	DestinationColor = uColor;
	TextureCoordOut = (uTexMatrix * vec3(inTexCoord, 1.0)).xy;
    gl_Position = Projection * Model * vec4(inVertex, 1.0);
}
