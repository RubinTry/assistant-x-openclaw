part of 'program.dart';

/// water distortion shader program
class M3ProgramWater extends M3ProgramLighting with M3WaterShader {
  M3ProgramWater(super.strVert, super.strFrag);

  @override
  void initLocation() {
    super.initLocation();

    initWaterLocation(program);
  }

  @override
  void setLightTBN(Vector3 tangent, Vector3 binormal, Vector3 normal) {
    super.setLightTBN(tangent, binormal, normal);
    // water TBN
    _setTBN(tangent, binormal, normal);
  }
}

/// water distortion shader program with CSM
class M3ProgramWaterCSM extends M3ProgramShadowCSM with M3WaterShader {
  M3ProgramWaterCSM(super.strVert, super.strFrag);

  @override
  void initLocation() {
    super.initLocation();

    initWaterLocation(program);
  }

  @override
  void setLightTBN(Vector3 tangent, Vector3 binormal, Vector3 normal) {
    super.setLightTBN(tangent, binormal, normal);
    // water TBN
    _setTBN(tangent, binormal, normal);
  }
}
