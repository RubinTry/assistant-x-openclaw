// Generated file – do not edit.
// ignore: constant_identifier_names
const String Simple_vert = r"""
#version 300 es
// Simple vert-shader ES3 //////////
// NOTICE: "Skinning.es3.vert" must be added before this file
#ifndef ENABLE_SKINNING
layout(location = 0) in highp vec3 inVertex;		// vertex-data
#endif // ENABLE_SKINNING

uniform lowp vec4 uColor;
out lowp vec4 DestinationColor;
// eye-space for camera-viewer
uniform highp mat4 ModelviewProjection;
		  
void main(void)
{
	highp vec4 objVert = vec4(inVertex, 1.0);

#ifdef ENABLE_SKINNING
	if (BoneCount > 0)
	{
		ComputeSkinningVertex(objVert);
	}
#endif // ENABLE_SKINNING

    DestinationColor = uColor; // use uniform color
    gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}

""";
