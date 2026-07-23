// Macbear3D engine
import '../m3_internal.dart';
import 'shadow_map.dart';

/// The WebGL rendering engine that manages shaders, framebuffers, and scene rendering.
///
/// Handles shader program creation, shadow mapping, 2D overlay rendering, and viewport management.
class M3RenderEngine {
  late RenderingContext gl;
  // reflection map
  late M3PlanarReflection planarReflection;

  // reflection probes
  final List<M3ReflectionProbe> probes = [];

  // shadow map
  M3ShadowMap? _shadowMap;
  M3ShadowMap? get shadowMap => _shadowMap;
  bool get isShadowEnabled => options.shadows && _shadowMap != null;

  /// main context (scene render)
  final M3RenderContext mainContext = M3RenderContext();

  // for ortho-matrix to project to 2D screen
  final _projection2D = M3Projection();

  // render options, statistics
  final M3RenderOptions options = M3RenderOptions();
  final M3RenderStats stats = M3RenderStats();

  // constructor
  M3RenderEngine() {
    M3Log.i('M3RenderEngine', 'constructor');
  }

  void init() {
    planarReflection = M3PlanarReflection();
  }

  void cleanProbes() {
    for (final probe in probes) {
      probe.dispose();
    }
    probes.clear();
  }

  void dispose() {
    _shadowMap?.dispose();
    planarReflection.dispose();
    cleanProbes();
  }

  /// Create shadow map, call only after WebGL context created
  void createShadowMap({int width = 1024, int height = 1024}) {
    _shadowMap ??= M3ShadowMap(width, height);
  }

  /// Bind default framebuffer
  void bindDefaultFramebuffer() {
    final engine = M3AppEngine.instance;
    final pixelW = (engine.appWidth * engine.devicePixelRatio).toInt();
    final pixelH = (engine.appHeight * engine.devicePixelRatio).toInt();
    gl.bindFramebuffer(WebGL.FRAMEBUFFER, M3AppEngine.mainFbo);
    gl.viewport(0, 0, pixelW, pixelH);
  }

  /// resize rendering engine when application size changed
  void resize(int width, int height, double dpr) {
    M3Log.i('M3RenderEngine', 'App resize ($width x $height) dpr: $dpr');

    final pixelW = (width * dpr).toInt();
    final pixelH = (height * dpr).toInt();

    // planar-reflection viewport by pixel size
    planarReflection.resize(width, height);

    // camera viewport by pixel size
    final scene = M3AppEngine.instance.activeScene;
    if (scene != null) {
      scene.camera.setViewport(0, 0, pixelW, pixelH);
      scene.water?.resize(width, height);
    }

    // projection 2D viewport by screen size
    _projection2D.setViewport(0, height, width, -height, fovy: 0, near: -1.0, far: 1.0);
    gl.lineWidth(dpr * 2.0);
  }

  /// Render shadow map
  void renderShadowMap(M3Scene scene) {
    if (options.debug.wireframe || !options.shadows) return;
    // directional light (ex: sun, moon)
    scene.dirLight.shadowMap?.renderDepth(scene, scene.dirLight);

    // point light
  }

  /// get program shader for scene rendering
  M3ProgramLighting getSceneProgram(M3Scene scene) {
    M3ProgramLighting prog = M3Resources.programTexture!; // texture shader

    if (isShadowEnabled) {
      // select shadow map shader: single or cascaded
      final M3ProgramShadow progShadow = scene.dirLight.cascades.isEmpty
          ? M3Resources.programShadowmap!
          : M3Resources.programShadowCSM!;
      prog = progShadow;
    }

    // M3ProgramLighting prog = M3Resources.programSimpleLighting!; // for debug
    return prog;
  }

  /// Render scene
  void renderScene(M3Scene scene) {
    stats.reset();
    stats.frames++;

    // draw skybox
    if (scene.skybox != null) {
      scene.skybox!.drawSkybox(scene.camera);
    }

    // set default GL state
    gl.frontFace(WebGL.CCW);
    gl.enable(WebGL.CULL_FACE);
    gl.enable(WebGL.DEPTH_TEST);
    gl.depthMask(true);
    gl.depthFunc(WebGL.LEQUAL);

    gl.enable(WebGL.BLEND);
    gl.blendFunc(WebGL.SRC_ALPHA, WebGL.ONE_MINUS_SRC_ALPHA); // WebGL.ONE

    if (!options.debug.wireframe) {
      // get scene program
      final prog = getSceneProgram(scene);

      prog.attachDirectionalLight(scene.dirLight);
      prog.attachPointLights(scene.pointLights);

      // main context render pass
      mainContext.render(prog);

      // reflection pass:
      // 1. cubemap reflection (only if not using single-pass IBL)
      // 2. planar reflection
      mainContext.renderReflectionPass();

      // post render water
      scene.water?.render();
    } else {
      // wireframe
      mainContext.render(M3Resources.programSimple!, fillMode: .wireframe);
      // water wireframe
      scene.water?.render(fillMode: .wireframe);
    }
  }

  /// Render 2D overlay, e.g. debug texts or other 2D elements
  void render2D() {
    // ortho-param: left, right, top, bottom, near, far (flip Y-axis by swap top/bottom)
    gl.disable(WebGL.DEPTH_TEST);
    gl.disable(WebGL.CULL_FACE);
    gl.enable(WebGL.BLEND);
    gl.blendFunc(WebGL.SRC_ALPHA, WebGL.ONE_MINUS_SRC_ALPHA);

    final prog2D = M3Resources.programRectangle!;
    gl.useProgram(prog2D.program);
    prog2D.setProjectionMatrix(_projection2D.projectionMatrix);

    gl.enableVertexAttribArray(prog2D.attribVertex.id);
    gl.enableVertexAttribArray(prog2D.attribUV.id);

    // draw rectangle full-screen
    final engine = M3AppEngine.instance;
    if (engine.activeScene != null) {
      engine.activeScene!.render2D();
    }

    // 2D helper
    if (options.debug.showMaps) {
      if (!options.debug.wireframe && options.shadows) {
        final sm = shadowMap;
        if (sm != null) {
          final width = 200 / sm.mapH * sm.mapW;
          sm.debugDrawDepth(5, engine.appHeight - 210, width, 200);
        }
      }
      // show planar reflection
      if (mainContext.needsPlanarReflectionPass()) {
        final engine = M3AppEngine.instance;
        final ratio = 0.33;
        final x = 110.0;
        final y = engine.appHeight - 210.0;
        final w = planarReflection.width * ratio;
        final h = planarReflection.height * ratio;

        planarReflection.debugDrawReflection(x, y, w, h);
      }

      final water = engine.activeScene?.water;
      if (water != null) {
        water.debugDraw();
      }

      prog2D.setModelMatrix(Matrix4.identity());

      // draw test: triangle, line, touches
      M3Shape2D.drawTouches(engine.touchManager);
    }
    // Render Statistics
    Matrix4 matStats = Matrix4.identity();
    if (options.debug.showStats) {
      matStats.setTranslation(Vector3(M3AppEngine.instance.appWidth - 100, 80, 0));
      matStats.scaleByVector3(Vector3.all(0.45));
      // Render Stats
      M3Resources.text2D.drawText(stats.toString(), matStats, color: Vector4(1, 1, 1, 1));

      if (engine.activeScene != null) {
        final scene = engine.activeScene!;

        final shadowText =
            '''
shadow:${options.shadows ? 'Y' : 'N'}
$shadowMap
csm=${scene.camera.csmCount}''';
        matStats.setTranslation(Vector3(M3AppEngine.instance.appWidth - 90, 150, 0));
        // Shadow Info
        M3Resources.text2D.drawText(shadowText, matStats, color: Vector4(1, 1, 0, 1));

        // reflection probes info
        final probesText = 'probes: ${probes.length}';
        matStats.setTranslation(Vector3(M3AppEngine.instance.appWidth - 90, 200, 0));
        M3Resources.text2D.drawText(probesText, matStats, color: Vector4(0, 1, 1, 1));
      }

      // FPS
      matStats.scaleByVector3(Vector3.all(1.4));
      final fpsText = engine.fps.toStringAsFixed(2);
      matStats.setTranslation(Vector3(M3AppEngine.instance.appWidth - 59, 221, 0));
      M3Resources.text2D.drawText(fpsText, matStats, color: Vector4(0, 0, 0, 1));
      matStats.setTranslation(Vector3(M3AppEngine.instance.appWidth - 60, 220, 0));
      final fpsColor = engine.fps > 30 ? Vector4(0, 1, 0, 1) : Vector4(1, 0, 0, 1);
      M3Resources.text2D.drawText(fpsText, matStats, color: fpsColor);
    }

    // Physics Statistics
    final physicsInfo = M3AppEngine.instance.activeScene?.physicsSystem.info;
    if (options.debug.showPhysicsStats && physicsInfo != null) {
      matStats.setTranslation(Vector3(10, 300, 0));
      M3Resources.text2D.drawText(physicsInfo, matStats, color: Vector4(1, 0, 1, 1));
    }

    gl.disableVertexAttribArray(prog2D.attribVertex.id);
    gl.disableVertexAttribArray(prog2D.attribUV.id);
  }
}
