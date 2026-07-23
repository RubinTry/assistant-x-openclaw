part of '../program.dart';

/// shadow shader in program
mixin M3ShadowShader {
  RenderingContext gl = M3AppEngine.instance.renderEngine.gl;

  // texture sampler for shadowmap
  late UniformLocation uniformSamplerShadowmap;
  late UniformLocation uniformShadowmapSize;
  late UniformLocation uniformNormalBias;

  void initShadowLocation(Program prog) {
    uniformSamplerShadowmap = gl.getUniformLocation(prog, "SamplerShadowmap");
    uniformShadowmapSize = gl.getUniformLocation(prog, "ShadowmapSize");
    uniformNormalBias = gl.getUniformLocation(prog, "NormalBias");

    if (M3Program.isLocationValid(uniformSamplerShadowmap)) {
      gl.uniform1i(uniformSamplerShadowmap, 3);
    }
  }

  /// Apply shadowmap related uniform variables.
  void _applyShadow(M3DirectionalLight light) {
    final shadowMap = light.shadowMap;
    if (shadowMap == null) return;

    // shadowmap texture
    if (M3Program.isLocationValid(uniformSamplerShadowmap)) {
      gl.activeTexture(WebGL.TEXTURE3);
      shadowMap.depthTex.bind();
      gl.uniform1i(uniformSamplerShadowmap, 3);

      gl.activeTexture(WebGL.TEXTURE0);
    }

    // shadowmap size
    if (M3Program.isLocationValid(uniformShadowmapSize)) {
      gl.uniform2f(uniformShadowmapSize, shadowMap.mapW.toDouble(), shadowMap.mapH.toDouble());
    }
    // shadowmap normal bias
    if (M3Program.isLocationValid(uniformNormalBias)) {
      gl.uniform1f(uniformNormalBias, light.shadowNormalBias);
    }
  }
}
