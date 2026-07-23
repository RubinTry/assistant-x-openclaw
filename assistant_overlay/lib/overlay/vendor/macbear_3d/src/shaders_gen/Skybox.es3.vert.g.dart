// Generated file – do not edit.
// ignore: constant_identifier_names
const String Skybox_vert = r"""
#version 300 es
// Skybox vert-shader ES3 //////////
layout(location = 0) in highp vec3 inVertex;		// vertex-data

uniform lowp vec4 uColor;
out lowp vec4 DestinationColor;
out mediump vec3 TexCoordDirOut;
// eye-space for camera-viewer
uniform highp mat4 ModelviewProjection;

void main(void)
{
	highp vec4 objVert = vec4(inVertex, 1.0);

	TexCoordDirOut = objVert.xyz;
	DestinationColor = uColor;
	gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}

""";
