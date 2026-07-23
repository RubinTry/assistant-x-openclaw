import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Macbear3D engine
import '../m3_internal.dart' hide Colors;
import '../input/keyboard.dart';

/// The main application engine singleton that manages the Flutter-ANGLE context.
///
/// Provides initialization, update loop, rendering, input handling, and scene management.
class M3AppEngine with ChangeNotifier {
  static final M3AppEngine instance = M3AppEngine._internal();

  static const String version = "macbear3d-lib v0.9.3 powered by ANGLE";
  final FlutterAngle _angle = FlutterAngle();
  late FlutterAngleTexture _sourceTexture; // main framebuffer
  static Framebuffer get mainFbo =>
      Framebuffer(kIsWeb ? null : instance._sourceTexture.fboId);
  static Vector4 backgroundColor = Vector4(0, 0, 0, 0);

  // did init engine completed
  bool _didInit = false; // context initialized
  Future<void> Function()? onDidInit;

  final M3RenderEngine renderEngine = M3RenderEngine();
  int initTick = 0;
  final M3TouchManager touchManager = M3TouchManager();
  final M3KeyboardManager keyboard = M3KeyboardManager();
  final M3ResourceManager resourceManager = M3ResourceManager();

  // update elspsed
  final Stopwatch _stopwatch = Stopwatch();

  late Ticker ticker;
  Duration _lastElapsed = Duration.zero;
  double timeScale = 1.0; // global time scale

  bool _updating = false;

  // FPS counter
  int _fpsFrameCount = 0;
  int _fpsLastTime = 0;
  double _currentFps = 0.0;
  double get fps => _currentFps;

  // app windows size
  int appWidth = 64;
  int appHeight = 64;
  double devicePixelRatio = 1.0; // Device Pixel Ratio

  // inset edges
  int edgeInsetLeft = 0;
  int edgeInsetTop = 0;
  int edgeInsetRight = 0;
  int edgeInsetBottom = 0;

  // scene
  M3Scene? activeScene;

  // This named constructor is the "real" constructor
  // It'll be called exactly once, by the static property assignment above
  // it's also private, so it can only be called in this class
  M3AppEngine._internal();

  Future<void> initApp({
    int width = 100,
    int height = 100,
    double dpr = 1.0,
  }) async {
    if (_didInit) {
      M3Log.w('AppEngine', 'initApp: context already initialized');
      return;
    }
    initTick = DateTime.now().millisecondsSinceEpoch;

    M3Log.s('AppEngine', version);
    M3Log.s(
      'AppEngine',
      '${PlatformInfo.getOS()}: initApp($width x $height)  dpr: $dpr',
    );

    initKeyboard();

    // auto determine rendering backend (ANGLE vs Native GLES)
    PlatformInfo.init();

    // init angle: ANGLE by Google
    await _angle.init(false, PlatformInfo.useAngle);
    final options = AngleOptions(
      width: width,
      height: height,
      dpr: dpr,
      useSurfaceProducer: true,
    );
    _sourceTexture = await _angle.createTexture(options);

    // init render engine
    renderEngine.gl = _sourceTexture.getContext();
    M3Log.i('AppEngine', 'ANGLE context ready');
    appWidth = width;
    appHeight = height;
    devicePixelRatio = dpr;

    // check OpenGL extensions
    // PlatformInfo.checkGLExtensions();

    // init resources
    await M3Resources.init();
    renderEngine.init();
    renderEngine.resize(width, height, dpr);

    _didInit = true;
    if (onDidInit != null) {
      await onDidInit!();
    }
    notifyListeners();
    M3Log.i('AppEngine', 'initApp done');
  }

  void initKeyboard() {
    keyboard.start();
    keyboard.onKeyDown = (e) {
      M3Log.d('AppEngine', 'KeyDown: ${e.logicalKey}');
      activeScene?.inputController?.onKeyDown(e);
    };

    keyboard.onKeyRepeat = (key) {
      M3Log.d('AppEngine', 'Repeat: ${key.debugName}');
      activeScene?.inputController?.onKeyRepeat(key);
    };

    keyboard.onKeyUp = (e) {
      M3Log.d('AppEngine', 'KeyUp: $e');
      activeScene?.inputController?.onKeyUp(e);
    };

    keyboard.onActionDown = (action) {
      M3Log.d('AppEngine', 'Action: $action');
    };
  }

  // dispose app
  @override
  void dispose() {
    // for keyboard
    keyboard.stop();

    // for ticker
    ticker.stop(canceled: true);
    ticker.dispose();

    // for render engine
    renderEngine.dispose();

    // for angle
    _angle.deleteTexture(_sourceTexture);
    _angle.dispose([_sourceTexture]);

    super.dispose();
  }

  Future<void> setScene(M3Scene scene) async {
    pause(); // app ticker pause

    // free probes
    renderEngine.cleanProbes();

    // free original scene
    if (M3AppEngine.instance.activeScene != null) {
      M3AppEngine.instance.activeScene!.dispose();
      M3AppEngine.instance.activeScene = null;
    }

    await scene.load();
    // reset scene to initial state
    scene.savePhysicsStates(); // Initial state for interpolation
    scene.update(0.0);

    activeScene = scene;
    renderEngine.resize(appWidth, appHeight, devicePixelRatio);

    notifyListeners();
    resume(); // app ticker resume
  }

  /// Triggers a rebuild of the engine UI by notifying listeners.
  void refresh() {
    notifyListeners();
  }

  void pause() {
    if (!_didInit) {
      return;
    }
    if (ticker.isActive) {
      ticker.stop();
    }
    M3Log.s('AppEngine', 'app pause');
  }

  void resume() {
    if (!_didInit) {
      return;
    }
    if (!ticker.isActive) {
      ticker.start();
      _lastElapsed = Duration.zero;
    }
    M3Log.s('AppEngine', 'app resume');
  }

  double _getTime() => DateTime.now().millisecondsSinceEpoch / 1000.0;

  Widget getAppWidget() {
    M3Log.s('AppEngine', 'getAppWidget');
    if (!_didInit) {
      // --- Macbear 3D ---
      // *** Copyright information, please do not delete
      // *** 版權所有, 請勿任意修改
      // *** 저작권은 보호되며, 허가 없이 수정할 수 없습니다.
      // #region DO NOT MODIFY --- Copyright
      return Container(
        color: Colors.grey,
        child: Center(
          child: Text(
            'Macbear 3D',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      );
      // #endregion
    }

    Widget textureSurface = kIsWeb
        ? HtmlElementView(viewType: _sourceTexture.textureId.toString())
        : _flipY(Texture(textureId: _sourceTexture.textureId));

    return Listener(
      onPointerDown: (event) {
        M3TouchPoint point = M3TouchPoint(
          Vector2(event.localPosition.dx, event.localPosition.dy),
          event.buttons,
          _getTime(),
        );
        M3Log.d(
          'AppEngine',
          'Pointer(${event.pointer}: down at ${point.toString()}',
        );
        final touch = touchManager.onTouchDown(event.pointer, point);
        activeScene?.inputController?.onTouchDown(touch);
      },
      onPointerMove: (event) {
        M3TouchPoint point = M3TouchPoint(
          Vector2(event.localPosition.dx, event.localPosition.dy),
          event.buttons,
          _getTime(),
        );
        // M3Log.d('AppEngine', 'Pointer(${event.pointer}: move at ${point.toString()}');
        final touch = touchManager.onTouchMove(event.pointer, point);
        if (touch != null) {
          activeScene?.inputController?.onTouchMove(touch);
        }
      },
      onPointerUp: (event) {
        M3TouchPoint point = M3TouchPoint(
          Vector2(event.localPosition.dx, event.localPosition.dy),
          event.buttons,
          _getTime(),
        );
        M3Log.d(
          'AppEngine',
          'Pointer(${event.pointer}: up at ${point.toString()}',
        );
        final touch = touchManager.onTouchUp(event.pointer, point);
        if (touch != null) {
          activeScene?.inputController?.onTouchUp(touch);
        }
        touchManager.clearInactive();
      },
      onPointerCancel: (event) {
        final Vector2 posTouch = Vector2(
          event.localPosition.dx,
          event.localPosition.dy,
        );
        M3Log.d('AppEngine', 'Pointer(${event.pointer}) cancel at: $posTouch');
        touchManager.touches.remove(event.pointer);
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          M3Log.d(
            'AppEngine',
            'Pointer(${event.pointer}) scroll: ${event.scrollDelta.dy}',
          );
          activeScene?.inputController?.onScroll(event.scrollDelta.dy);
        }
      },
      child: textureSurface,
    );
  }

  Future<bool> onResize(int width, int height, double dpr) async {
    M3Log.i(
      'AppEngine',
      'onResize: ($width x $height) dpr: $dpr (init=$_didInit)',
    );
    if (!_didInit) {
      return false;
    }

    if (width == appWidth && height == appHeight && dpr == devicePixelRatio) {
      M3Log.w('AppEngine', 'onResize: ignore');
      return false;
    }

    // so resize it
    final options = AngleOptions(
      width: width,
      height: height,
      dpr: dpr,
      useSurfaceProducer: true,
    );
    if (PlatformInfo.isAndroid) {
      await _angle.deleteTexture(_sourceTexture);
      _sourceTexture = await _angle.createTexture(options);
      // M3RenderEngine.gl = _sourceTexture.getContext();
    } else {
      await _angle.resize(_sourceTexture, options);
    }

    appWidth = width;
    appHeight = height;
    devicePixelRatio = dpr;

    renderEngine.resize(width, height, dpr);

    // touch manager reset
    touchManager.clearAll();
    return true;
  }

  // application update and render
  // elapsed time since ticker started (absolute duration)
  Future<void> updateRender(Duration elapsed) async {
    if (!_updating && _didInit) {
      _updating = true;

      try {
        // delta time since last frame (relative duration)
        Duration delta = elapsed - _lastElapsed;
        final Duration maxDelta = Duration(milliseconds: 40);
        if (delta > maxDelta) {
          delta = maxDelta;
        }
        _lastElapsed = elapsed;

        _stopwatch.reset();
        _stopwatch.start();

        // check shader update if dirty
        M3Resources.checkUpdate(renderEngine.options.shader);
        // application update then render
        _update(delta);
        await _render();

        _stopwatch.stop();

        // FPS calculation
        _fpsFrameCount++;
        int now = DateTime.now().millisecondsSinceEpoch;
        if (now - _fpsLastTime >= 1000) {
          _currentFps = _fpsFrameCount * 1000.0 / (now - _fpsLastTime);
          _fpsLastTime = now;
          _fpsFrameCount = 0;
        }
      } catch (e) {
        M3Log.e('AppEngine', 'updateRender: $e');
      } finally {
        _updating = false;
      }
    } else {
      M3Log.w('AppEngine', 'Too slow');
    }
  }

  // application update
  void _update(Duration delta) {
    double dt = delta.inMicroseconds / 1000000.0;
    double sdt = dt * timeScale;
    // M3Log.d('AppEngine', 'update= $delta');

    final scene = activeScene;
    if (scene != null) {
      scene.inputController?.update(dt);
      scene.update(sdt);
    }
  }

  // application render
  Future<void> _render() async {
    // 1. pre-render: shadow map, reflection, etc.
    final scene = activeScene;
    if (scene != null) {
      // shadow map
      renderEngine.renderShadowMap(scene);

      // prepare render queue
      renderEngine.mainContext.prepareRenderQueue(scene, scene.camera);

      // capture reflection probe (environment map)
      if (renderEngine.mainContext.needsReflectionProbePass()) {
        for (var probe in renderEngine.probes) {
          probe.captureProbe(scene);
        }
      }
      // capture planar reflection
      if (renderEngine.mainContext.needsPlanarReflectionPass()) {
        renderEngine.planarReflection.captureReflection(scene);
      }

      final water = scene.water;
      if (water != null) {
        water.captureWater();
      }
    }

    _sourceTexture.activate();

    final gl = renderEngine.gl;
    gl.clearColor(
      backgroundColor.r,
      backgroundColor.g,
      backgroundColor.b,
      backgroundColor.a,
    );
    gl.clear(WebGL.COLOR_BUFFER_BIT | WebGL.DEPTH_BUFFER_BIT);

    // 2. render active scene
    if (scene != null) {
      renderEngine.renderScene(scene);

      // draw debug: only implement when needed
      scene.debugDraw();

      // draw Helper
      if (renderEngine.options.debug.showHelpers) {
        scene.drawHelper();
      }

      // draw camera frustums
      if (renderEngine.options.debug.showCamera) {
        scene.drawCameraHelper();
        // for debug camera frustum only
        M3Resources.debugCamera?.drawHelper(
          M3Resources.programSimple!,
          scene.camera,
        );

        if (renderEngine.mainContext.needsPlanarReflectionPass()) {
          // renderEngine.planarReflection.drawReflectionCamera(scene.camera); // remark for ignore
        }
      }

      // draw light helper
      if (renderEngine.options.debug.showLight) {
        if (M3Resources.debugCamera != null) {
          // for debug directional light frustum only
          scene.dirLight.updateShadowCascades(M3Resources.debugCamera!);
        }
        scene.dirLight.drawHelper(M3Resources.programSimple!, scene.camera);
        scene.drawLightHelper(drawBulb: false);
      }
      if (renderEngine.options.debug.lightBulb) {
        scene.drawLightHelper();
      }
    }
    // 3. render 2D: UI, text etc.
    renderEngine.render2D();

    gl.flush();
    // gl.finish(); // Macbear note: discard it

    await _sourceTexture.signalNewFrameAvailable();
  }

  Widget _flipY(Widget widgetSrc) {
    // Flip Y only for Metal/iOS, Windows
    if (PlatformInfo.isIOS || PlatformInfo.isMacOS || PlatformInfo.isWindows) {
      return Transform.scale(scaleY: -1.0, child: widgetSrc);
    } else {
      return widgetSrc;
    }
  }
}
