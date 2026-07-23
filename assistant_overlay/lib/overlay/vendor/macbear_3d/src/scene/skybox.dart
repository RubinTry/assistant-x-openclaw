// Macbear3D engine
import '../m3_internal.dart';

/// A skybox rendered using a cubemap texture.
///
/// Renders a background environment that follows the camera position.
class M3Skybox {
  static RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;
  final M3Texture cubemapTexture;

  M3Skybox(this.cubemapTexture);

  static Future<M3Skybox> createCubemap(
    String urlPosX,
    String urlNegX,
    String urlPosY,
    String urlNegY,
    String urlPosZ,
    String urlNegZ,
  ) async {
    final tex = await M3Texture.loadCubemap(urlPosX, urlNegX, urlPosY, urlNegY, urlPosZ, urlNegZ);
    return M3Skybox(tex);
  }

  void dispose() {
    cubemapTexture.dispose();
  }

  /// draw skybox
  void drawSkybox(M3Camera camera) {
    final scale = camera.farClip / 4;
    Matrix4 mat = Matrix4.identity();
    // rotate axisX 90 degree: up from axisY to axisZ
    mat.setRotation(M3Constants.rotXNeg90);
    mat.scaleByVector3(Vector3.all(-scale));
    mat.setTranslation(camera.position);

    drawCube(camera, mat, cubemapTexture, writeDepth: false);
  }

  static void drawCube(M3Camera camEye, Matrix4 boxMatrix, M3Texture cubeTexture, {bool writeDepth = true}) {
    gl.depthMask(writeDepth);
    if (writeDepth) {
      gl.enable(WebGL.DEPTH_TEST);
    } else {
      gl.disable(WebGL.DEPTH_TEST);
    }

    gl.disable(WebGL.CULL_FACE);
    gl.disable(WebGL.BLEND);

    // pre-draw
    final prog = M3Resources.programSkybox!;
    gl.useProgram(prog.program);
    M3Material mtr = M3Material()..setGlossy();
    // draw on target for debug
    prog.setMatrices(camEye, boxMatrix);
    prog.setMaterial(mtr, Vector4.all(1.0));
    prog.setEnvironmentMap(cubeTexture);

    M3Resources.debugFrustum.draw(prog, fillMode: .solid);

    gl.depthMask(true);
    gl.enable(WebGL.DEPTH_TEST);
    gl.enable(WebGL.CULL_FACE);
    gl.enable(WebGL.BLEND);
  }
}
