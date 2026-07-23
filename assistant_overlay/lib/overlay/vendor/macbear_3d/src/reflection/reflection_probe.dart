// Macbear3D engine
import '../m3_internal.dart';

class M3ReflectionProbe {
  final _camCapture = M3Camera();
  M3Entity? owner; // ignore capture entity

  final M3RenderContext _context = M3RenderContext();
  late M3Framebuffer _framebuffer;
  int texSize = 128;
  M3Texture get cubemapTexture => _framebuffer.colorTexture;

  bool isMirror = true;

  M3ReflectionProbe({this.texSize = 128, this.isMirror = true, double near = 0.1, double far = 200.0}) {
    // Temporary camera with 90 degree FOV
    _camCapture.csmCount = 0;
    _camCapture.setViewport(0, 0, texSize, texSize, fovy: 90.0, near: near, far: far);
    _framebuffer = M3Framebuffer(texSize, texSize)
      ..createColorTexture(target: WebGL.TEXTURE_CUBE_MAP)
      ..createDepthRenderbuffer();
  }

  void dispose() {
    _framebuffer.dispose();
  }

  void setOwner(M3Entity? owner) {
    this.owner = owner;
  }

  /// Capture the scene from the probe's position into a cubemap texture.
  void captureProbe(M3Scene scene) {
    if (owner == null) return;
    Vector3 position = owner!.position;

    final renderEngine = M3AppEngine.instance.renderEngine;
    final gl = renderEngine.gl;

    double mirrorX = isMirror ? -1 : 1;
    final targets = [
      Vector3(mirrorX, 0, 0),
      Vector3(-mirrorX, 0, 0),
      Vector3(0, 0, 1),
      Vector3(0, 0, -1),
      Vector3(0, -1, 0),
      Vector3(0, 1, 0),
    ];
    final ups = [
      Vector3(0, 0, -1),
      Vector3(0, 0, -1),
      Vector3(0, -1, 0),
      Vector3(0, 1, 0),
      Vector3(0, 0, -1),
      Vector3(0, 0, -1),
    ];
    final faces = [
      WebGL.TEXTURE_CUBE_MAP_POSITIVE_X,
      WebGL.TEXTURE_CUBE_MAP_NEGATIVE_X,
      WebGL.TEXTURE_CUBE_MAP_POSITIVE_Y,
      WebGL.TEXTURE_CUBE_MAP_NEGATIVE_Y,
      WebGL.TEXTURE_CUBE_MAP_POSITIVE_Z,
      WebGL.TEXTURE_CUBE_MAP_NEGATIVE_Z,
    ];

    final prog = M3Resources.programTexture!;
    prog.attachDirectionalLight(scene.dirLight);
    prog.attachPointLights(scene.pointLights);

    for (int i = 0; i < 6; i++) {
      // Bind FBO, then attach texture face
      _framebuffer.bind();
      cubemapTexture.attachToFramebuffer(WebGL.COLOR_ATTACHMENT0, faces[i]);

      // Clear
      final bg = M3AppEngine.backgroundColor;
      gl.clearColor(bg.r, bg.g, bg.b, 1.0);
      gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);

      // Setup camera
      _camCapture.setLookat(position, position + targets[i], ups[i]);

      if (isMirror) {
        _camCapture.refreshProjectionMatrix();
        _camCapture.projectionMatrix.scaleByVector3(Vector3(-1, 1, 1));
      }

      // Render skybox
      if (scene.skybox != null) {
        scene.skybox!.drawSkybox(_camCapture);
      }
      // set default GL state
      gl.frontFace(isMirror ? WebGL.CW : WebGL.CCW);
      gl.enable(WebGL.CULL_FACE);
      gl.enable(WebGL.DEPTH_TEST);
      gl.depthMask(true);
      gl.depthFunc(WebGL.LEQUAL);

      gl.enable(WebGL.BLEND);
      gl.blendFuncSeparate(
        WebGL.SRC_ALPHA,
        WebGL.ONE_MINUS_SRC_ALPHA,
        WebGL.ONE,
        WebGL.ONE_MINUS_SRC_ALPHA,
      );

      // render scene for cubemap face
      _context.prepareRenderQueue(scene, _camCapture);
      if (owner != null) {
        // ignore exclude entity
        _context.excludeEntities([owner!]);
      }
      _context.render(prog);
    }
    cubemapTexture.generateMipmap();
    // Restore state
    renderEngine.bindDefaultFramebuffer();
  }
}
