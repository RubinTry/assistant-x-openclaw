import 'package:web/web.dart' as web;
import '../log.dart';
import 'platform_info.dart';

bool isPlatformAndroid() => false;
bool isPlatformIOS() => false;
bool isPlatformMacOS() => false;
bool isPlatformWindows() => false;

String getPlatformName() {
  return 'Browser';
}

/// Mock flag for web consistency.
bool useAngleAndroid = true;

void initPlatformImpl() {}

web.WebGLRenderingContext? getWebGL() {
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
  // Try WebGL 2 first
  var gl = canvas.getContext('webgl2') as web.WebGLRenderingContext?;
  gl ??= canvas.getContext('webgl') as web.WebGLRenderingContext?;

  return gl;
}

void getGLExtensions() {
  final gl = getWebGL();
  if (gl == null) return;

  final extensions = gl.getSupportedExtensions();
  if (extensions != null) {
    M3Log.i('PlatformInfo', 'Supported WebGL Extensions:');
    for (var i = 0; i < extensions.length; i++) {
      M3Log.i('PlatformInfo', '${extensions[i]}');
    }
  }
}

void getEGLExtensions() {
  M3Log.w('PlatformInfo', 'EGL info not available on Web (using WebGL)');
}

GraphicsInfo getGpuInfo() {
  final gl = getWebGL();
  if (gl == null) {
    return const GraphicsInfo(vendor: 'Unknown', renderer: 'Unknown', version: 'Unknown', shadingVersion: 'Unknown');
  }

  String vendor = gl.getParameter(web.WebGLRenderingContext.VENDOR)?.toString() ?? 'Unknown';
  String renderer = gl.getParameter(web.WebGLRenderingContext.RENDERER)?.toString() ?? 'Unknown';
  String version = gl.getParameter(web.WebGLRenderingContext.VERSION)?.toString() ?? 'Unknown';
  String shadingVersion = gl.getParameter(web.WebGLRenderingContext.SHADING_LANGUAGE_VERSION)?.toString() ?? 'Unknown';

  // Try to get unmasked vendor and renderer if extension is available
  final extension = gl.getExtension('WEBGL_debug_renderer_info') as web.WEBGL_debug_renderer_info?;
  if (extension != null) {
    // UNMASKED_VENDOR_WEBGL = 0x9245 (37445)
    // UNMASKED_RENDERER_WEBGL = 0x9246 (37446)
    final unmaskedVendor = gl.getParameter(web.WEBGL_debug_renderer_info.UNMASKED_VENDOR_WEBGL);
    final unmaskedRenderer = gl.getParameter(web.WEBGL_debug_renderer_info.UNMASKED_RENDERER_WEBGL);
    if (unmaskedVendor != null) vendor = unmaskedVendor.toString();
    if (unmaskedRenderer != null) renderer = unmaskedRenderer.toString();
  }

  return GraphicsInfo(vendor: vendor, renderer: renderer, version: version, shadingVersion: shadingVersion);
}
