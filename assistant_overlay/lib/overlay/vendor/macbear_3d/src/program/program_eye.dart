part of 'program.dart';

// add reflection by skybox-cubemap
class M3ProgramEye extends M3Program {
  late UniformLocation uniformEyePosition; // eye position as camera origin
  late UniformLocation uniformInvObjScale; // inverse object scale

  M3ProgramEye(super.strVert, super.strFrag, {super.reflectionType});

  @override
  void initLocation() {
    super.initLocation();

    uniformEyePosition = gl.getUniformLocation(program, "uEyePos");
    uniformInvObjScale = gl.getUniformLocation(program, "uInvObjScale");
  }

  @override
  void setMatrices(M3Camera cam, Matrix4 mMatrix, [Matrix4? mMatrixInv]) {
    super.setMatrices(cam, mMatrix, mMatrixInv);

    if (M3Program.isLocationValid(uniformEyePosition)) {
      // ModelView matrix
      Matrix4 mvMatrix = cam.viewMatrix * mMatrix;

      // object-space position
      Matrix4 matInv = Matrix4.identity();
      double det = matInv.copyInverse(mvMatrix);

      if (det != 0.0) {
        // eye position in object-space (model-space)
        if (M3Program.isLocationValid(uniformEyePosition)) {
          Vector3 eyePosition = matInv.getTranslation();
          gl.uniform3fv(uniformEyePosition, eyePosition.storage);
        }
        // inverse object scale
        if (M3Program.isLocationValid(uniformInvObjScale)) {
          Vector3 invObjScale = matInv.decomposeScale();
          invObjScale.x = 1.0 / invObjScale.x;
          invObjScale.y = 1.0 / invObjScale.y;
          invObjScale.z = 1.0 / invObjScale.z;
          gl.uniform3fv(uniformInvObjScale, invObjScale.storage);
        }
      } else {
        M3Log.w('M3ProgramEye', 'setMatrices: det is ZERO!');
      }
    }
  }
}
