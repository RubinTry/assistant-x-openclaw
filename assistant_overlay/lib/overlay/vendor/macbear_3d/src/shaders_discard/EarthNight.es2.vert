// Lighting function //////////
attribute mediump vec2 inTexCoord;
//attribute mediump vec4 inColor;		// as diffuse-ambient material

// color combined by light and material
uniform lowp vec4 ColorDiffuse;		// diffuse RGBA
uniform mediump vec4 ColorSpecular;	// specular RGB, w: shininess
uniform lowp vec3 ColorAmbient;		// ambient RGB

// object space
uniform mediump vec3 EyePosition;	// eye as camera origin
uniform mediump vec3 LightPosition;	// parallel light

// shader variable: from vert to frag
varying lowp vec4 DestinationColor;
varying mediump vec2 TextureCoordOut;

// eye-space for camera-viewer
//uniform mat4 Projection;
uniform mat4 ModelviewProjection;

void main(void)
{
	highp vec4 objVert = vec4(inVertex, 1.0);
	mediump vec3 objNormal = inNormal;
	
	if (BoneCount > 0)
	{
		ComputeSkinningVertex(objVert, objNormal);
	}
	
	// object-space: normal, light-position, eye-position
	mediump vec3 L = LightPosition;							// parallel light source

	mediump float df = dot(objNormal, L);
#define VAL_A	0.0
#define VAL_B	0.18  //0.2
	if (df <= VAL_A)
		df = 1.0;
	else if (df < VAL_B)
		df = (VAL_B - df) / (VAL_B - VAL_A);
	else
		df = 0.0;
	
	DestinationColor = vec4(ColorAmbient + ColorDiffuse.rgb * df, ColorDiffuse.a);
	
	TextureCoordOut = inTexCoord;
	gl_Position = ModelviewProjection * objVert;	// pre-compute Projection * Modelview
}
