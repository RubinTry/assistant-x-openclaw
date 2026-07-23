// Simple vert-shader //////////
// NOTICE: "Skinning.es2.vert" must be added before this file
#ifndef ENABLE_SKINNING
attribute highp vec3 inVertex;		// vertex-data
#endif // ENABLE_SKINNING

// attribute mediump vec4 inColor;		// as diffuse-ambient material

uniform lowp vec4 uColor;
varying lowp vec4 DestinationColor;
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
