part of 'program.dart';

/// abstract shadow program: lighting + shadow + fog
abstract class M3ProgramShadow extends M3ProgramLighting with M3ShadowShader {
  M3ProgramShadow(super.strVert, super.strFrag);

  @override
  void initLocation() {
    super.initLocation();

    initShadowLocation(program);
  }

  @override
  void applyUniforms(M3Camera cam) {
    super.applyUniforms(cam);
    // for shadowmap: apply shadow
    _applyShadow(_dirLight!);
  }
}

/// shadowmap program
class M3ProgramShadowmap extends M3ProgramShadow {
  late UniformLocation uniformMatrixShadowmap;

  M3ProgramShadowmap(super.strVert, super.strFrag);

  @override
  void initLocation() {
    super.initLocation();

    uniformMatrixShadowmap = gl.getUniformLocation(program, "MatrixShadowmap");
  }

  @override
  void setMatrices(M3Camera cam, Matrix4 mMatrix, [Matrix4? mMatrixInv]) {
    super.setMatrices(cam, mMatrix, mMatrixInv);

    if (M3Program.isLocationValid(uniformMatrixShadowmap)) {
      final viewer = _dirLight!.lightViewer;
      // light-space
      Matrix4 lightMatrix = viewer.projectionMatrix * viewer.viewMatrix * mMatrix;
      Matrix4 shadowMatrix = M3Constants.biasMatrix * lightMatrix;
      gl.uniformMatrix4fv(uniformMatrixShadowmap, false, shadowMatrix.storage);
    }
  }
}

// shadow CSM program
class M3ProgramShadowCSM extends M3ProgramShadow {
  late UniformLocation uniformMatrixCSM;
  late UniformLocation uniformDepthCSM;

  M3ProgramShadowCSM(super.strVert, super.strFrag);

  @override
  void initLocation() {
    super.initLocation();

    uniformMatrixCSM = gl.getUniformLocation(program, "MatrixCSM");
    uniformDepthCSM = gl.getUniformLocation(program, "DepthCSM");
  }

  @override
  void applyUniforms(M3Camera cam) {
    super.applyUniforms(cam);

    if (M3Program.isLocationValid(uniformDepthCSM)) {
      final maxCSM = 4;
      final numCSM = min(maxCSM, cam.csmCount);

      Float32List depthBuffer = Float32List(maxCSM);
      for (int i = 0; i < numCSM; i++) {
        // eye-depth to frag-z
        final eyeDepth = cam.csmSplitDistances[i + 1];
        depthBuffer[i] = cam.eyeDepthToFragZFromMatrix(eyeDepth);
      }
      gl.uniform4fv(uniformDepthCSM, depthBuffer);
    }
  }

  @override
  void setMatrices(M3Camera cam, Matrix4 mMatrix, [Matrix4? mMatrixInv]) {
    super.setMatrices(cam, mMatrix, mMatrixInv);

    final light = _dirLight!;
    if (M3Program.isLocationValid(uniformMatrixCSM)) {
      final maxCSM = 4;
      final numCSM = min(maxCSM, light.cascades.length);

      Float32List matricesBuffer = Float32List(maxCSM * 16);
      Matrix4 biasMatrix = Matrix4.copy(M3Constants.biasMatrix);

      for (int i = 0; i < numCSM; i++) {
        final cascade = light.cascades[i];
        // bias matrix
        final halfH = cascade.atlasScaleV / 2;
        biasMatrix.setEntry(1, 1, halfH);
        biasMatrix.setEntry(1, 3, halfH + cascade.atlasBiasV);

        // light-space
        Matrix4 lightMatrix = cascade.projectionMatrix * light.lightViewer.viewMatrix * mMatrix;
        Matrix4 shadowMatrix = biasMatrix * lightMatrix;
        matricesBuffer.setRange(i * 16, i * 16 + 16, shadowMatrix.storage);
      }

      gl.uniformMatrix4fv(uniformMatrixCSM, false, matricesBuffer);
    }
  }
}
