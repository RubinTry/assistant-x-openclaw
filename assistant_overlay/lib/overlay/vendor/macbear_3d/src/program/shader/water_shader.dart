part of '../program.dart';

/// water shader in program
mixin M3WaterShader {
  RenderingContext gl = M3AppEngine.instance.renderEngine.gl;

  late UniformLocation uniformBumpTranslateScale0; // bump translation, scale
  late UniformLocation uniformBumpTranslateScale1; // bump translation, scale
  late UniformLocation uniformWaveDistortion; // wave distortion

  // tangent-space: tangent, binormal, normal
  late UniformLocation uniformAxisTangent;
  late UniformLocation uniformAxisBinormal;
  late UniformLocation uniformAxisNormal;

  void initWaterLocation(Program prog) {
    uniformBumpTranslateScale0 = gl.getUniformLocation(prog, "BumpTranslateScale0");
    uniformBumpTranslateScale1 = gl.getUniformLocation(prog, "BumpTranslateScale1");
    uniformWaveDistortion = gl.getUniformLocation(prog, "WaveDistortion");

    uniformAxisTangent = gl.getUniformLocation(prog, "AxisTangent");
    uniformAxisBinormal = gl.getUniformLocation(prog, "AxisBinormal");
    uniformAxisNormal = gl.getUniformLocation(prog, "AxisNormal");

    // Set the sampler2D variables
    gl.uniform1i(gl.getUniformLocation(prog, "NormalTex"), 1); // GL_TEXTURE1
    gl.uniform1i(gl.getUniformLocation(prog, "RefractionTex"), 2); // GL_TEXTURE2
  }

  /// bind water reflection, refraction, bump, etc.
  void bindWater(M3Water water) {
    // Bind texture
    gl.activeTexture(WebGL.TEXTURE1);
    water.normalMap.bind();

    gl.activeTexture(WebGL.TEXTURE2);
    if (water.refractionPass.enable) {
      water.refractionPass.texture.bind();
    } else {
      M3Resources.texWhite.bind();
    }

    // diffuse by reflection
    gl.activeTexture(WebGL.TEXTURE0);
    if (water.reflectionPass.enable) {
      water.reflectionPass.texture.bind();
    } else {
      M3Resources.texWhite.bind();
    }

    // uniform param for bump of water (per GLSL)
    final bump0 = water.flow0;
    final bump1 = water.flow1;
    gl.uniform4f(uniformBumpTranslateScale0, bump0.offset.x, bump0.offset.y, bump0.scale.x, bump0.scale.y);
    gl.uniform4f(uniformBumpTranslateScale1, bump1.offset.x, bump1.offset.y, bump1.scale.x, bump1.scale.y);
    gl.uniform1f(uniformWaveDistortion, water.waveDistortion);
  }

  void _setTBN(Vector3 tangent, Vector3 binormal, Vector3 normal) {
    // tangent-space: tangent, binormal, normal
    gl.uniform3fv(uniformAxisTangent, tangent.storage);
    gl.uniform3fv(uniformAxisBinormal, binormal.storage);
    gl.uniform3fv(uniformAxisNormal, normal.storage);
  }
}
