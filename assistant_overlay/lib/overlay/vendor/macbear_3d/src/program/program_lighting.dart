part of 'program.dart';

/// lighting program: lighting + fog
class M3ProgramLighting extends M3ProgramEye with M3LightingShader, M3FogShader {
  M3ProgramLighting(super.strVert, super.strFrag, {super.reflectionType});

  @override
  void initLocation() {
    super.initLocation();

    initLightingLocation(program);
    initFogLocation(program);
  }

  void setLightTBN(Vector3 tangent, Vector3 binormal, Vector3 normal) {
    if (_dirLight != null) {
      Vector3 lightDir = _dirLight!.getDirection();
      Vector3 tbnDir = Vector3(lightDir.dot(tangent), lightDir.dot(binormal), lightDir.dot(normal));
      gl.uniform3fv(uniformLightDirection, tbnDir.storage);
    }
  }

  @override
  void setMatrices(M3Camera cam, Matrix4 mMatrix, [Matrix4? mMatrixInv]) {
    super.setMatrices(cam, mMatrix, mMatrixInv);

    setLightUniforms(mMatrix);
    setFogPlane(cam, mMatrix);
  }

  @override
  void setMaterial(M3Material mtr, Vector4 color) {
    super.setMaterial(mtr, color);

    Vector4 outDiffuse = M3Light.blendRGBA(mtr.diffuse, color);

    // ambient: RGB
    if (M3Program.isLocationValid(uniformAmbient)) {
      Vector3 outAmbient = M3Light.blendRGB(M3Light.ambient, outDiffuse.rgb);
      gl.uniform3fv(uniformAmbient, outAmbient.storage);
    }

    // diffuse: RGBA
    if (M3Program.isLocationValid(uniformDiffuse)) {
      outDiffuse.xyz = M3Light.blendRGB(_dirLight!.color, outDiffuse.rgb);
      gl.uniform4fv(uniformDiffuse, outDiffuse.storage);
    }

    // specular: RGB
    if (M3Program.isLocationValid(uniformSpecular)) {
      Vector3 outSpecular = M3Light.blendRGB(mtr.specular, color.rgb);
      outSpecular = M3Light.blendRGB(_dirLight!.color, outSpecular);

      // Pass as vec4: RGB, w = Shininess
      gl.uniform4f(uniformSpecular, outSpecular.x, outSpecular.y, outSpecular.z, mtr.shininess);
    }
  }
}
