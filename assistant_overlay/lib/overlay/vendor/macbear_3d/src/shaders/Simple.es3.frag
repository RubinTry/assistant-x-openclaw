#version 300 es
precision mediump float;
// Simple frag-shader ES3 //////////

in lowp vec4 DestinationColor;
out vec4 fragColor;

void main(void)
{
    fragColor = DestinationColor;
}
