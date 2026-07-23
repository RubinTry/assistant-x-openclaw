// Macbear3D engine
import '../m3_internal.dart';

/// Shadow map renderer for real-time shadows from directional lights.
///
/// Renders the scene from the light's perspective to generate a depth texture.
class M3ShadowMap {
  final M3RenderContext _context = M3RenderContext();

  final M3Framebuffer _framebuffer;
  int get mapW => _framebuffer.frameW;
  int get mapH => _framebuffer.frameH;
  M3Texture get depthTex => _framebuffer.depthTexture;

  M3ShadowMap(int width, int height) : _framebuffer = M3Framebuffer(width, height)..createDepthTexture() {
    M3Log.i('M3ShadowMap', 'create FBO: $width x $height');
  }

  @override
  String toString() {
    return '$mapW*$mapH';
  }

  void dispose() {
    _framebuffer.dispose();
  }

  /// Render depth map from light's perspective
  void renderDepth(M3Scene scene, M3DirectionalLight light) {
    final renderEngine = M3AppEngine.instance.renderEngine;
    final gl = renderEngine.gl;
    final prog = M3Resources.programSimple!;

    final stats = renderEngine.stats;
    final bool wasStatsEnabled = stats.enabled;
    stats.enabled = false;

    _framebuffer.bind();
    // set shadow GL state
    gl.frontFace(WebGL.CCW);
    gl.enable(WebGL.CULL_FACE);
    gl.enable(WebGL.DEPTH_TEST);
    gl.depthMask(true);
    gl.depthFunc(WebGL.LEQUAL);

    gl.disable(WebGL.BLEND);
    gl.enable(WebGL.POLYGON_OFFSET_FILL);
    // render front-face and positive offset to avoid shadow acne
    // gl.polygonOffset(.3, .2);
    gl.polygonOffset(1.1, 4.0);

    gl.clear(WebGL.DEPTH_BUFFER_BIT);

    // prepare CSM
    light.updateShadowCascades(scene.cameras[0]);
    final lightViewer = light.lightViewer;

    // check if use cascaded shadow map
    if (light.cascades.isNotEmpty) {
      // cascaded shadow mapping
      final backupMatrix = lightViewer.projectionMatrix;
      for (final cascade in light.cascades) {
        // viewport for the cascaded-shadow
        final int y = (cascade.atlasBiasV * mapH).toInt();
        final int height = (cascade.atlasScaleV * mapH).toInt();
        gl.viewport(0, y, mapW, height);
        lightViewer.projectionMatrix = cascade.projectionMatrix;
        // frustum matrix for culling
        lightViewer.updateFrustum();
        // shadowmap render scene only opaque
        _context.prepareRenderQueue(scene, lightViewer, bOnlyOpaque: true);
        _context.render(prog);
      }
      lightViewer.projectionMatrix = backupMatrix;
      lightViewer.updateFrustum();
    } else {
      lightViewer.updateFrustum();
      // shadowmap render scene only opaque
      _context.prepareRenderQueue(scene, lightViewer, bOnlyOpaque: true);
      _context.render(prog);
    }

    // recover to default GL state
    gl.polygonOffset(0, 0);
    gl.disable(WebGL.POLYGON_OFFSET_FILL);
    gl.enable(WebGL.BLEND);

    // recover to default FBO
    renderEngine.bindDefaultFramebuffer();
    stats.enabled = wasStatsEnabled;
  }

  /// Draw shadow depth map for debugging
  void debugDrawDepth(double x, double y, double width, double height) {
    M3Texture depthTex = _framebuffer.depthTexture;
    // size 200x200
    final scale = Vector3(width / depthTex.texW, height / depthTex.texH, 1.0);
    depthTex.debugDraw(x, y, scale.x, scale.y);
  }
}
