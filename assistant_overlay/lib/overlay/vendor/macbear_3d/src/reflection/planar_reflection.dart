// Macbear3D engine
import '../m3_internal.dart';

enum M3PlanarPass { reflection, refraction }

class M3PlanarReflection {
  final M3RenderContext _context = M3RenderContext();
  late M3Framebuffer _framebuffer;

  /// get reflection pixel size
  int get width => texture.texW;
  int get height => texture.texH;
  M3Texture get texture => _framebuffer.colorTexture;

  final Plane clipPlane = Plane.components(0, 0, 1, 0);
  final M3Camera _camera = M3Camera(); // reflection camera to render reflection
  final double farClipRatio = 0.5;

  bool enable = true;
  bool visible = true;
  double _renderScale;

  /// width / height: default size of reflection image
  /// resolutionScale: scale ratio of width and height
  M3PlanarReflection({int width = 16, int height = 16, double resolutionScale = 0.5}) : _renderScale = resolutionScale {
    assert(resolutionScale > 0 && resolutionScale <= 1.0);
    _framebuffer = M3Framebuffer(width, height)
      ..createColorTexture()
      ..createDepthRenderbuffer();
  }

  void setRenderScale(double scale) {
    assert(scale > 0 && scale <= 1.0);
    _renderScale = scale;
    resize(width, height);
  }

  /// Resize reflection image, size is based on display size
  void resize(int width, int height) {
    if (!enable) return;

    width = max((width * _renderScale).toInt(), 2);
    height = max((height * _renderScale).toInt(), 2);
    if (width == this.width && height == this.height) return;

    dispose();
    _framebuffer = M3Framebuffer(width, height)
      ..createColorTexture()
      ..createDepthRenderbuffer();
  }

  void dispose() {
    _framebuffer.dispose();
  }

  void _capture(M3Scene scene, M3PlanarPass pass) {
    if (!enable) return;
    // visible only when camera is above the plane
    final dist = clipPlane.distanceToVector3(scene.camera.position);
    visible = dist > 0.01;
    if (!visible) return;

    _camera.setFrom(scene.camera);

    // shrink far clip for culling shadow casters
    _camera.farClip *= farClipRatio;
    _camera.refreshProjectionMatrix();
    _camera.updateSplitDistances();

    if (pass == M3PlanarPass.reflection) {
      // reversed winding for mirrored view
      _camera.reflectViewMatrix(clipPlane);
    } else {
      // normal winding — no view flip
    }

    _renderToTexture(scene, pass);
  }

  /// Capture the scene by planar reflection (renders above the plane).
  void captureReflection(M3Scene scene) {
    _capture(scene, M3PlanarPass.reflection);
  }

  /// Capture the scene by planar refraction (renders below the plane).
  void captureRefraction(M3Scene scene) {
    _capture(scene, M3PlanarPass.refraction);
  }

  // Render the scene to [_texture]
  // reflection pass: render above water (mirror)
  // refraction pass: render below water (inside water)
  void _renderToTexture(M3Scene scene, M3PlanarPass pass) {
    final renderEngine = M3AppEngine.instance.renderEngine;
    final gl = renderEngine.gl;

    // Bind FBO, then attach texture face
    _framebuffer.bind();
    texture.attachToFramebuffer(WebGL.COLOR_ATTACHMENT0, WebGL.TEXTURE_2D);

    // Clear
    final bg = Vector3(0, 0, 0);
    gl.clearColor(bg.r, bg.g, bg.b, 1.0);
    gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);

    if (scene.skybox != null) {
      scene.skybox!.drawSkybox(_camera);
    }

    // oblique clip:
    // reflection: clip geometry below the water, use original plane
    // refraction: clip geometry above the water, use negated plane
    final bool isReflection = pass == M3PlanarPass.reflection;
    final n = clipPlane.normal;
    final bias = 0; // 0.1
    final d = clipPlane.constant - bias;
    final p = isReflection ? Plane.normalconstant(n, d) : Plane.normalconstant(-n, -d);
    _camera.setObliqueClipPlane(p);
    _camera.updateFrustum();

    final int frontFace = isReflection ? WebGL.CW : WebGL.CCW;

    // GL state
    gl.frontFace(frontFace);
    gl.enable(WebGL.CULL_FACE);
    gl.enable(WebGL.DEPTH_TEST);

    gl.depthMask(true);
    gl.depthFunc(WebGL.LEQUAL);

    gl.enable(WebGL.BLEND);
    gl.blendFunc(WebGL.SRC_ALPHA, WebGL.ONE_MINUS_SRC_ALPHA); // WebGL.ONE

    gl.enable(WebGL.POLYGON_OFFSET_FILL);
    gl.polygonOffset(1.1, 4.0);

    // get scene program
    final prog = renderEngine.getSceneProgram(scene);

    prog.attachDirectionalLight(scene.dirLight);
    prog.attachPointLights(scene.pointLights);

    // (1/2) prepare render queue: exclude this plane
    _context.prepareRenderQueue(scene, _camera, excludeReflection: this);

    // (2/2) render scene for planar reflection/refraction
    _context.render(prog);

    texture.generateMipmap();

    gl.frontFace(WebGL.CCW); // Restore
    gl.polygonOffset(0, 0);
    gl.disable(WebGL.POLYGON_OFFSET_FILL);
    renderEngine.bindDefaultFramebuffer();
  }

  /// draw reflection camera
  void drawReflectionCamera(M3Camera viewer) {
    if (!enable || !visible) return;

    M3Camera mirrorCamera = _camera;
    if (M3Resources.debugCamera != null) {
      mirrorCamera = M3Resources.debugCamera!.clone();
      // shrink far clip for culling shadow casters
      mirrorCamera.farClip *= farClipRatio;
      mirrorCamera.refreshProjectionMatrix();
      mirrorCamera.updateSplitDistances();

      // reversed winding for mirrored view
      mirrorCamera.reflectViewMatrix(clipPlane);
      mirrorCamera.setObliqueClipPlane(clipPlane);
      mirrorCamera.updateFrustum();
    }
    mirrorCamera.drawHelper(M3Resources.programSimple!, viewer);
  }

  /// Draw reflection map for debugging
  void debugDrawReflection(double x, double y, double width, double height) {
    if (!enable || !visible) return;

    final scale = Vector3(width / this.width, height / this.height, 1.0);
    texture.debugDraw(x, y, scale.x, scale.y);
  }
}
