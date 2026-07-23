// Rect vert-shader //////////
attribute highp vec3 inVertex;		// vertex-data
//attribute mediump vec4 inColor;		// as diffuse-ambient material
attribute mediump vec2 inTexCoord;

uniform lowp vec4 uColor;

// eye-space for camera-viewer
uniform highp mat4 Projection;		// ortho-matrix
uniform highp mat4 Model;			// model-matrix (by screen-object)

uniform highp mat3 uTexMatrix;		// texture-matrix (uv mapping)
varying mediump vec2 TextureCoordOut;
varying lowp vec4 DestinationColor;

void main(void)
{
	DestinationColor = uColor;
	TextureCoordOut = (uTexMatrix * vec3(inTexCoord, 1.0)).xy;
	// TextureCoordOut = inTexCoord;
    gl_Position = Projection * Model * vec4(inVertex, 1.0);
}
