/// Rendering options for the engine (wireframe, helpers, shadows, FPS display).
class M3RenderOptions {
  // debug options
  M3DebugOptions debug = M3DebugOptions();
  // shader options
  M3ShaderOptions shader = M3ShaderOptions();
  bool shadows = true;
}

class M3DebugOptions {
  bool wireframe = false;
  bool showHelpers = false;
  bool showCamera = false; // camera frustum
  bool showLight = false; // light helper
  bool showMaps = false; // texture maps
  bool showStats = true;
  bool showPhysicsStats = false;

  bool lightBulb = true; // point light bulb
}

// GLSL options
class M3ShaderOptions {
  bool _perPixel = true; // per-pixel lighting
  bool _cartoon = false; // cartoon shading
  bool _pbr = true; // physics based rendering
  bool _ibl = true; // image based lighting
  int _pcf = 1; // shadow PCF: 0:none, 1:default(4-tap), 2:3x3, 3:5x5
  bool _fog = false;

  bool isDirty = false;

  // --- fog ---
  bool get fog => _fog;
  set fog(bool v) {
    if (_fog == v) return;
    _fog = v;
    isDirty = true;
  }

  // --- perPixel ---
  bool get perPixel => _perPixel;
  set perPixel(bool v) {
    if (_perPixel == v) return;
    _perPixel = v;
    isDirty = true;

    // perPixel 關閉時，cartoon 與 pbr 一定要關
    if (!_perPixel) {
      if (_cartoon) _cartoon = false;
      if (pbr) pbr = false; // 這也會自動連動關閉 ibl
    }
  }

  // --- cartoon ---
  bool get cartoon => _cartoon;
  set cartoon(bool v) {
    if (_cartoon == v) return;
    _cartoon = v;
    isDirty = true;

    // cartoon 開啟時，自動強制 perPixel, 並關閉 pbr
    if (_cartoon) {
      if (!_perPixel) perPixel = true;
      if (pbr) pbr = false;
    }
  }

  // --- pbr ---
  bool get pbr => _pbr;
  set pbr(bool v) {
    if (_pbr == v) return;
    _pbr = v;
    isDirty = true;

    // pbr 開啟時，自動強制 perPixel, 並關閉 cartoon
    if (_pbr) {
      if (!_perPixel) perPixel = true;
      if (cartoon) _cartoon = false;
    } else {
      // pbr 關閉時，ibl 也要關閉
      _ibl = false;
    }
  }

  // --- ibl ---
  bool get ibl => _ibl;
  set ibl(bool v) {
    if (_ibl == v) return;
    _ibl = v;
    isDirty = true;

    // ibl 開啟時，自動強制 pbr
    if (_ibl) {
      if (!pbr) pbr = true;
    }
  }

  // --- pcf ---
  int get pcf => _pcf;
  set pcf(int v) {
    if (_pcf == v) return;
    _pcf = v;
    isDirty = true;
  }
}

/// Rendering statistics
class M3RenderStats {
  bool enabled = true;
  int frames = 0;
  int vertices = 0;
  int triangles = 0;
  int entities = 0;
  int culling = 0;
  int reflection = 0;

  void reset() {
    if (!enabled) return;
    vertices = 0;
    triangles = 0;
    entities = 0;
    culling = 0;
    reflection = 0;
  }

  @override
  String toString() {
    return '''
frame${frames.toString().padLeft(6)}
mesh:$entities/$culling
reflect:$reflection
 tri:$triangles
vert:$vertices''';
  }
}
