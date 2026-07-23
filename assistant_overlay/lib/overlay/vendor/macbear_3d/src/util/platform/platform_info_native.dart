import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart'; // 需要 pkg:ffi

// Macbear3D engine
import '../../m3_internal.dart';
import 'platform_info_vulkan.dart';

bool isPlatformAndroid() => Platform.isAndroid;
bool isPlatformIOS() => Platform.isIOS;
bool isPlatformMacOS() => Platform.isMacOS;
bool isPlatformWindows() => Platform.isWindows;

String getPlatformName() {
  return Platform.operatingSystem; // Android, iOS, Windows, etc.
}

/// Global flag to control ANGLE usage on Android.
/// Can be set before engine initialization.
bool useAngleAndroid = true;

void initPlatformImpl() {
  if (Platform.isAndroid) {
    bool hasVulkan = PlatformInfoVulkan.shouldInitVulkan();
    useAngleAndroid = hasVulkan;
    M3Log.i('PlatformInfo', 'Android GPU Detection (init)');
    M3Log.i('PlatformInfo', 'Vulkan Support Detected: $hasVulkan');
    M3Log.i('PlatformInfo', 'Current useAngle setting: $useAngleAndroid');
  }
}

void getGLExtensions() {
  final gl = M3AppEngine.instance.renderEngine.gl;
  if (!kIsWeb) {
    int numExt = gl.getIntegerv(0x821D);
    for (int i = 0; i < numExt; i++) {
      final s0 = gl.getStringi(WebGL.EXTENSIONS, i);
      M3Log.i('GLext', '$i = $s0');
    }
  }
}

typedef EglGetCurrentDisplayC = Pointer<Void> Function();
typedef EglGetCurrentDisplayDart = Pointer<Void> Function();

typedef EglQueryStringC = Pointer<Uint8> Function(Pointer<Void> display, Int32 name);
typedef EglQueryStringDart = Pointer<Uint8> Function(Pointer<Void> display, int name);

void getEGLExtensions() {
  final eglLib = _loadEGLLib();
  if (eglLib == null) {
    M3Log.e('EGL', 'EGL library not found');
    return;
  }

  // ignore: constant_identifier_names
  const int EGL_EXTENSIONS = 0x3055;
  try {
    final EglGetCurrentDisplayDart eglGetCurrentDisplay = eglLib
        .lookup<NativeFunction<EglGetCurrentDisplayC>>('eglGetCurrentDisplay')
        .asFunction();
    final EglQueryStringDart eglQueryString = eglLib
        .lookup<NativeFunction<EglQueryStringC>>('eglQueryString')
        .asFunction();

    final display = eglGetCurrentDisplay();
    M3Log.i('EGL', 'EGL Display: $display');

    // 1. Client Extensions (Display is EGL_NO_DISPLAY = nullptr)
    final clientExtsPtr = eglQueryString(nullptr, EGL_EXTENSIONS);
    if (clientExtsPtr.address != 0) {
      M3Log.i('EGL', 'EGL Client Extensions:');
      _printExtensionList(clientExtsPtr.cast<Utf8>().toDartString());
    }

    // 2. Display Extensions
    if (display.address != 0) {
      final displayExtsPtr = eglQueryString(display, EGL_EXTENSIONS);
      if (displayExtsPtr.address != 0) {
        M3Log.i('EGL', 'EGL Display Extensions:');
        _printExtensionList(displayExtsPtr.cast<Utf8>().toDartString());
      }
    }
  } catch (e) {
    M3Log.e('EGL', 'Error querying EGL extensions: $e');
  } finally {
    eglLib.close();
  }
}

void _printExtensionList(String extensions) {
  final list = extensions.split(' ');
  for (var i = 0; i < list.length; i++) {
    final ext = list[i].trim();
    if (ext.isNotEmpty) {
      M3Log.d('EGLext', '$i = $ext');
    }
  }
}

DynamicLibrary? _loadGLESv2Lib() {
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      return DynamicLibrary.open('libGLESv2.framework/libGLESv2');
    } catch (e) {
      return DynamicLibrary.open('libGLESv2');
    }
  } else if (Platform.isAndroid) {
    if (useAngleAndroid) {
      try {
        return DynamicLibrary.open('libGLESv2_angle.so');
      } catch (e) {
        // Fallback to native
        return DynamicLibrary.open('libGLESv2.so');
      }
    } else {
      return DynamicLibrary.open('libGLESv2.so');
    }
  } else if (Platform.isWindows) {
    try {
      return DynamicLibrary.open('libGLESv2.dll');
    } catch (e) {
      return DynamicLibrary.open('libGLESv2_angle.dll');
    }
  }

  return null;
}

DynamicLibrary? _loadEGLLib() {
  if (Platform.isMacOS || Platform.isIOS) {
    try {
      return DynamicLibrary.open('libEGL.framework/libEGL');
    } catch (e) {
      return DynamicLibrary.open('libEGL');
    }
  } else if (Platform.isAndroid) {
    if (useAngleAndroid) {
      try {
        return DynamicLibrary.open('libEGL_angle.so');
      } catch (e) {
        return DynamicLibrary.open('libEGL.so');
      }
    } else {
      return DynamicLibrary.open('libEGL.so');
    }
  } else if (Platform.isWindows) {
    try {
      return DynamicLibrary.open('libEGL.dll');
    } catch (e) {
      return DynamicLibrary.open('libEGL_angle.dll');
    }
  }
  return null;
}

// 定義 C 函式的簽名
typedef GLGetStringC = Pointer<Uint8> Function(Uint32 name);
typedef GLGetStringDart = Pointer<Uint8> Function(int name);

String safeGetString(Pointer<Uint8> ptr) {
  if (ptr.address == 0) return "Unknown";
  return ptr.cast<Utf8>().toDartString();
}

GraphicsInfo getGpuInfo() {
  if (Platform.isAndroid) {
    M3Log.i('Android GPU', 'Current useAngle setting: $useAngleAndroid');
  }

  final glesLib = _loadGLESv2Lib();
  if (glesLib == null) {
    return const GraphicsInfo(vendor: "None", renderer: "None", version: "None", shadingVersion: "None");
  }
  final GLGetStringDart glGetString = glesLib.lookup<NativeFunction<GLGetStringC>>('glGetString').asFunction();

  Pointer<Uint8> vendorPtr = glGetString(WebGL.VENDOR);
  Pointer<Uint8> rendererPtr = glGetString(WebGL.RENDERER);
  Pointer<Uint8> versionPtr = glGetString(WebGL.VERSION);
  Pointer<Uint8> shaderPtr = glGetString(WebGL.SHADING_LANGUAGE_VERSION);

  // 將 C 指標轉為 Dart String
  String vendor = safeGetString(vendorPtr);
  String renderer = safeGetString(rendererPtr);
  String version = safeGetString(versionPtr);
  String glslVer = safeGetString(shaderPtr);
  GraphicsInfo ret = GraphicsInfo(vendor: vendor, renderer: renderer, version: version, shadingVersion: glslVer);

  glesLib.close();
  return ret;
}
