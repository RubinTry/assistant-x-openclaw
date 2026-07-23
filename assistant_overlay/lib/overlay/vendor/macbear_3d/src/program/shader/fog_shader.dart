part of '../program.dart';

/// fog shader in program
mixin M3FogShader {
  RenderingContext gl = M3AppEngine.instance.renderEngine.gl;

  // sphere fog
  late UniformLocation uniformFogParams; // x: sphereStart, y: sphereDepth, z: planeHeight
  late UniformLocation uniformFogColor;

  // plane fog: height in fogParams.z
  late UniformLocation uniformPlaneFog;
  late UniformLocation uniformPlaneFogColor;

  M3Fog? _fog;

  void initFogLocation(Program prog) {
    // sphere fog
    uniformFogParams = gl.getUniformLocation(prog, "uFogParams");
    uniformFogColor = gl.getUniformLocation(prog, "uFogColor");

    // plane fog
    uniformPlaneFog = gl.getUniformLocation(prog, "uPlaneFog");
    uniformPlaneFogColor = gl.getUniformLocation(prog, "uPlaneFogColor");
  }

  void applyFog(M3Fog fog) {
    bool fogEnabled = false;

    // 1. set sphere fog
    if (M3Program.isLocationValid(uniformFogColor) && M3Program.isLocationValid(uniformFogParams)) {
      gl.uniform3f(uniformFogParams, fog.start, fog.depth, fog.planeHeight);
      gl.uniform3fv(uniformFogColor, fog.color.storage);
      fogEnabled = true;
    }
    // 2. set plane fog
    if (M3Program.isLocationValid(uniformPlaneFogColor)) {
      gl.uniform3fv(uniformPlaneFogColor, fog.planeColor.storage);
      fogEnabled = true;
    }
    _fog = fogEnabled ? fog : null;
  }

  void setFogPlane(M3Camera camera, Matrix4 worldMatrix) {
    final fog = _fog;
    if (fog == null) return;

    if (!M3Program.isLocationValid(uniformPlaneFog)) {
      M3Log.w('M3FogShader', 'Fog uniformPlaneFog not found');
      return;
    }

    // custom water plane, use opposite plane normal for refraction fog pass inside water
    final p = fog.plane;
    final worldPlane = -Vector4(p.normal.x, p.normal.y, p.normal.z, p.constant);

    // Transform world space plane to object space:
    final worldMatrixTransposed = Matrix4.copy(worldMatrix)..transpose();
    final objectPlane = worldMatrixTransposed * worldPlane;

    gl.uniform4fv(uniformPlaneFog, objectPlane.storage);
  }
}
