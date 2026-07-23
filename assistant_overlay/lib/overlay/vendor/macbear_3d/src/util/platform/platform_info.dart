// 1. 預設匯入 native: 編譯環境有 dart.library.io (Mobile/Desktop)
import 'platform_info_native.dart'
    // 2. 如果編譯環境有 dart.library.js_interop (Web)，改用 web 版
    if (dart.library.js_interop) 'platform_info_web.dart';

// Macbear3D engine
import '../../m3_internal.dart';

class GraphicsInfo {
  final String vendor;
  final String renderer;
  final String version;
  final String shadingVersion;

  const GraphicsInfo({
    required this.vendor,
    required this.renderer,
    required this.version,
    required this.shadingVersion,
  });

  @override
  String toString() {
    return '''
[ Graphics Information ]
------------------------------
Vendor: $vendor
Renderer: $renderer
Version: $version
Shading version: $shadingVersion
''';
  }
}

class PlatformInfo {
  // Platform checks
  static bool get isAndroid => isPlatformAndroid();
  static bool get isIOS => isPlatformIOS();
  static bool get isMacOS => isPlatformMacOS();
  static bool get isWindows => isPlatformWindows();

  static void init() {
    initPlatformImpl();
  }

  static String getOS() {
    return getPlatformName();
  }

  /// Controls whether ANGLE (GLES-over-Vulkan/Backend) is used on Android.
  /// Set this to false to force native OpenGLES.
  static bool get useAngle => useAngleAndroid;
  static set useAngle(bool value) => useAngleAndroid = value;

  // GPU info: Vendor, Renderer, GLSL version
  static GraphicsInfo getGraphicsInfo() {
    final info = getGpuInfo();
    M3Log.s('GPU Info', '$info');
    return info;
  }

  static const Map<int, String> _glParamNames = {
    WebGL.MAX_TEXTURE_IMAGE_UNITS: "MAX_TEXTURE_IMAGE_UNITS",
    WebGL.MAX_VERTEX_TEXTURE_IMAGE_UNITS: "MAX_VERTEX_TEXTURE_IMAGE_UNITS",
    WebGL.MAX_TEXTURE_SIZE: "MAX_TEXTURE_SIZE",
    WebGL.MAX_CUBE_MAP_TEXTURE_SIZE: "MAX_CUBE_MAP_TEXTURE_SIZE",
    WebGL.MAX_VERTEX_ATTRIBS: "MAX_VERTEX_ATTRIBS",
    WebGL.MAX_VERTEX_UNIFORM_VECTORS: "MAX_VERTEX_UNIFORM_VECTORS",
    WebGL.MAX_VARYING_VECTORS: "MAX_VARYING_VECTORS",
    WebGL.MAX_FRAGMENT_UNIFORM_VECTORS: "MAX_FRAGMENT_UNIFORM_VECTORS",
    WebGL.MAX_SAMPLES: "MAX_SAMPLES",
    WebGL.MAX_COMBINED_TEXTURE_IMAGE_UNITS: "MAX_COMBINED_TEXTURE_IMAGE_UNITS",
    WebGL.SCISSOR_BOX: "SCISSOR_BOX",
    WebGL.VIEWPORT: "VIEWPORT",
    WebGL.MAX_TEXTURE_MAX_ANISOTROPY_EXT: "MAX_TEXTURE_MAX_ANISOTROPY_EXT",
    WebGL.MAX_UNIFORM_BUFFER_BINDINGS: "MAX_UNIFORM_BUFFER_BINDINGS",
  };

  static void checkGLExtensions() {
    final gl = M3AppEngine.instance.renderEngine.gl;

    _glParamNames.forEach((key, name) {
      final val = gl.getParameter(key);
      M3Log.s('GL Info', '$name = $val');
    });

    getGLExtensions();
    getEGLExtensions();
  }

  /// WebGL function: enable extension, ex. compressed texture
  static bool enableWebGLExtension(String extension) {
    if (!kIsWeb) return true;

    final gl = M3AppEngine.instance.renderEngine.gl;
    final ext = gl.getExtension(extension);
    M3Log.h('WebGL', 'Enable extension: $extension, ${ext != null ? "success" : "fail"}');
    return ext != null;
  }
}
