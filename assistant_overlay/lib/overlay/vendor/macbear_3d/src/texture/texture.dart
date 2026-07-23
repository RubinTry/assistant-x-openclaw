import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Matrix4;

// Macbear3D engine
import '../m3_internal.dart' hide Colors;
import 'ktx_info.dart';

// parts for texture
part 'text_texture.dart';

/// WebGL texture wrapper supporting 2D and cubemap textures.
///
/// Provides methods for loading from assets, creating solid colors, and checkerboard patterns.
class M3Texture {
  RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;

  // default white pixel 1x1
  static final List<int> _cubeMapFaceTargets = [
    WebGL.TEXTURE_CUBE_MAP_POSITIVE_X,
    WebGL.TEXTURE_CUBE_MAP_NEGATIVE_X,
    WebGL.TEXTURE_CUBE_MAP_POSITIVE_Y,
    WebGL.TEXTURE_CUBE_MAP_NEGATIVE_Y,
    WebGL.TEXTURE_CUBE_MAP_POSITIVE_Z,
    WebGL.TEXTURE_CUBE_MAP_NEGATIVE_Z,
  ];

  String name = "noname";
  late WebGLTexture _texture;
  int get glId => _texture.id;
  final bool useMipmaps;
  final int target; // GL_TEXTURE_2D, GL_TEXTURE_CUBE_MAP
  int texW = 32;
  int texH = 32;

  /// Get the mathematically correct maximum mipmap level based on dimensions
  int get maxMipLevel => (log(max(texW, texH)) / ln2).floor();

  M3Texture({this.target = WebGL.TEXTURE_2D, this.useMipmaps = true, int? wrap}) {
    _texture = gl.createTexture();

    setParameters(wrap: wrap);
  }

  void setParameters({int? wrap}) {
    final bool isCubemap = target == WebGL.TEXTURE_CUBE_MAP;
    final int wrapMode = wrap ?? (isCubemap ? WebGL.CLAMP_TO_EDGE : WebGL.REPEAT);

    bind();
    // wrap: (s, t, r)
    gl.texParameteri(target, WebGL.TEXTURE_WRAP_S, wrapMode);
    gl.texParameteri(target, WebGL.TEXTURE_WRAP_T, wrapMode);
    if (isCubemap) {
      gl.texParameteri(target, WebGL.TEXTURE_WRAP_R, wrapMode);
    }

    // filter: (min, mag)
    final minFilter = useMipmaps ? WebGL.LINEAR_MIPMAP_LINEAR : WebGL.LINEAR;
    gl.texParameteri(target, WebGL.TEXTURE_MIN_FILTER, minFilter); // NEAREST, GL_LINEAR_MIPMAP_LINEAR
    gl.texParameteri(target, WebGL.TEXTURE_MAG_FILTER, WebGL.LINEAR); // NEAREST
    gl.pixelStorei(WebGL.UNPACK_ALIGNMENT, 1);
  }

  void dispose() {
    gl.deleteTexture(_texture);
  }

  /// attach texture to framebuffer
  void attachToFramebuffer(int attachment, int texTarget) {
    gl.framebufferTexture2D(WebGL.FRAMEBUFFER, attachment, texTarget, _texture, 0);
  }

  /// bind texture
  void bind() {
    gl.bindTexture(target, _texture);
  }

  static final WebGLTexture _textureNone = WebGLTexture(kIsWeb ? null : 0);
  void unbind() {
    return;
    // ignore: dead_code
    gl.bindTexture(target, _textureNone); // seems not necessary
  }

  /// Generate mipmaps for the texture.
  void generateMipmap() {
    if (useMipmaps) {
      bind();
      gl.generateMipmap(target);
    }
  }

  /// Create a texture from a WebGL texture.
  M3Texture.fromWebGLTexture(this._texture, {this.texW = 1024, this.texH = 1024, this.useMipmaps = false})
    : target = WebGL.TEXTURE_2D;

  @override
  String toString() {
    final targetName = switch (target) {
      WebGL.TEXTURE_2D => '2D',
      WebGL.TEXTURE_CUBE_MAP => 'CubeMap',
      _ => 'Unknown',
    };
    return 'Texture $targetName ($texW x $texH): "$name"';
  }

  /// Create a solid color texture (2D) with specified color.
  static M3Texture createSolidColor(Vector4 color) {
    M3Texture tex = M3Texture(useMipmaps: false);
    tex.name = "solid_color";
    tex._initColorPixel(color);
    return tex;
  }

  /// Create a solid color cubemap (cube) with specified color.
  static M3Texture createSolidColorCube(Vector4 color) {
    M3Texture tex = M3Texture(target: WebGL.TEXTURE_CUBE_MAP, useMipmaps: false);
    tex.name = "solid_color_cube";
    for (int i = 0; i < 6; i++) {
      tex._initColorPixel(color, faceTarget: _cubeMapFaceTargets[i]);
    }
    return tex;
  }

  /// Create a default IBL cubemap with simple sky/ground gradient colors.
  static M3Texture createDefaultIBLCube() {
    const int size = 16;
    M3Texture tex = M3Texture(target: WebGL.TEXTURE_CUBE_MAP, useMipmaps: true)
      ..name = "default_ibl_cube"
      ..texW = size
      ..texH = size;

    final colorSky = Vector4(0.5, 0.7, 0.9, 1.0); // Light bluish sky
    final colorGround = Vector4(0.2, 0.2, 0.2, 1.0); // Dark neutral gray ground
    final colorHorizon = Vector4(0.5, 0.5, 0.5, 1.0); // Neutral gray horizon

    Vector4 lerpColor(Vector4 a, Vector4 b, double t) {
      return Vector4(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t);
    }

    final Uint8List data = Uint8List(size * size * 4);

    for (int faceIndex = 0; faceIndex < 6; faceIndex++) {
      final faceTarget = _cubeMapFaceTargets[faceIndex];
      int offset = 0;

      for (int j = 0; j < size; j++) {
        final double v = (j + 0.5) / size * 2.0 - 1.0;
        for (int i = 0; i < size; i++) {
          final double u = (i + 0.5) / size * 2.0 - 1.0;

          // Determine the 3D direction vector based on WebGL/OpenGL cubemap face conventions:
          // https://www.khronos.org/opengl/wiki/Cubemap_Texture
          double x = 0;
          double y = 0;
          double z = 0;

          switch (faceIndex) {
            case 0: // +X (Right)
              x = 1.0;
              y = -v;
              z = -u;
              break;
            case 1: // -X (Left)
              x = -1.0;
              y = -v;
              z = u;
              break;
            case 2: // +Y (Top)
              x = u;
              y = 1.0;
              z = v;
              break;
            case 3: // -Y (Bottom)
              x = u;
              y = -1.0;
              z = -v;
              break;
            case 4: // +Z (Back/Front)
              x = u;
              y = -v;
              z = 1.0;
              break;
            case 5: // -Z (Front/Back)
              x = -u;
              y = -v;
              z = -1.0;
              break;
          }

          final double len = sqrt(x * x + y * y + z * z);
          final double dx = x / len;
          final double dy = y / len;

          Vector4 color;
          if (dy >= 0.0) {
            color = lerpColor(colorHorizon, colorSky, sqrt(dy));
          } else {
            color = lerpColor(colorHorizon, colorGround, sqrt(-dy));
          }

          // Apply directional color biases:
          // - +X and -X directions get a subtle red bias (proportional to |dx|)
          // - +Y and -Y directions get a subtle green bias (proportional to |dy|)
          final double r = (color.r + dx.abs() * 0.15).clamp(0.0, 1.0);
          final double g = (color.g + dy.abs() * 0.10).clamp(0.0, 1.0);
          final double b = color.b;
          final double a = color.a;

          data[offset] = (r * 255.0).round().clamp(0, 255);
          data[offset + 1] = (g * 255.0).round().clamp(0, 255);
          data[offset + 2] = (b * 255.0).round().clamp(0, 255);
          data[offset + 3] = (a * 255.0).round().clamp(0, 255);
          offset += 4;
        }
      }

      tex.bind();
      tex.gl.texImage2D(faceTarget, 0, WebGL.RGBA, size, size, 0, WebGL.RGBA, WebGL.UNSIGNED_BYTE, toU8List(data));
    }

    tex.generateMipmap();
    return tex;
  }

  /// Create an empty 2D texture with a specified size.
  static M3Texture createEmpty2D(int width, int height, {bool useMipmaps = true, int? wrap}) {
    M3Texture tex = M3Texture(useMipmaps: useMipmaps, wrap: wrap)
      ..name = "empty_2d_${width}x$height"
      ..texW = width
      ..texH = height
      .._initEmptyTarget(faceTarget: WebGL.TEXTURE_2D);

    return tex;
  }

  /// Create an empty cubemap with a specified size (all 6 faces filled with a neutral gray color).
  static M3Texture createEmptyCubemap(int size) {
    M3Texture tex = M3Texture(target: WebGL.TEXTURE_CUBE_MAP, useMipmaps: true)
      ..name = "empty_cubemap_${size}x$size"
      ..texW = size
      ..texH = size;

    for (int i = 0; i < 6; i++) {
      tex._initEmptyTarget(faceTarget: _cubeMapFaceTargets[i]);
    }
    return tex;
  }

  void _initColorPixel(Vector4 color, {int faceTarget = WebGL.TEXTURE_2D}) {
    texW = 1;
    texH = 1;

    // Fill the texture with a 1x1 white pixel.
    final pixel = Uint8List.fromList([
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
      (color.a * 255).round().clamp(0, 255),
    ]);
    gl.texImage2D(faceTarget, 0, WebGL.RGBA, 1, 1, 0, WebGL.RGBA, WebGL.UNSIGNED_BYTE, toU8List(pixel));
  }

  void _initEmptyTarget({int faceTarget = WebGL.TEXTURE_2D}) {
    gl.texImage2D(faceTarget, 0, WebGL.RGBA, texW, texH, 0, WebGL.RGBA, WebGL.UNSIGNED_BYTE, null);
  }

  void _initCheckerboard(int gridCount, Vector4 lightColor, Vector4 darkColor, {int faceTarget = WebGL.TEXTURE_2D}) {
    texW = gridCount;
    texH = gridCount;

    gl.texParameteri(target, WebGL.TEXTURE_MIN_FILTER, WebGL.NEAREST); // NEAREST, GL_LINEAR_MIPMAP_LINEAR
    gl.texParameteri(target, WebGL.TEXTURE_MAG_FILTER, WebGL.NEAREST); // NEAREST

    // Fill the texture with a checkerboard pattern.
    final lightPixel = Uint8List.fromList([
      (lightColor.r * 255).round().clamp(0, 255),
      (lightColor.g * 255).round().clamp(0, 255),
      (lightColor.b * 255).round().clamp(0, 255),
      (lightColor.a * 255).round().clamp(0, 255),
    ]);
    final darkPixel = Uint8List.fromList([
      (darkColor.r * 255).round().clamp(0, 255),
      (darkColor.g * 255).round().clamp(0, 255),
      (darkColor.b * 255).round().clamp(0, 255),
      (darkColor.a * 255).round().clamp(0, 255),
    ]);

    final data = Uint8List.fromList(List.generate(gridCount * gridCount * 4, (index) => 0));
    for (int i = 0; i < gridCount; i++) {
      for (int j = 0; j < gridCount; j++) {
        final pixel = (i + j) % 2 == 0 ? lightPixel : darkPixel;
        final index = (i * gridCount + j) * 4;
        data[index] = pixel[0];
        data[index + 1] = pixel[1];
        data[index + 2] = pixel[2];
        data[index + 3] = pixel[3];
      }
    }

    gl.texImage2D(faceTarget, 0, WebGL.RGBA, gridCount, gridCount, 0, WebGL.RGBA, WebGL.UNSIGNED_BYTE, toU8List(data));
  }

  /// Create a checkerboard texture (2D) with specified size and colors.
  static M3Texture createCheckerboard({
    int size = 4,
    Vector4? lightColor,
    Vector4? darkColor,
    int faceTarget = WebGL.TEXTURE_2D,
  }) {
    M3Texture tex = M3Texture();
    lightColor ??= Vector4(0.8, 0.8, 0.8, 1);
    darkColor ??= Vector4(0.5, 0.5, 0.5, 1);
    tex.name = 'checkerboard';
    tex._initCheckerboard(size, lightColor, darkColor, faceTarget: faceTarget);
    tex.generateMipmap();
    return tex;
  }

  /// Create a sampler cubemap for texture sampling test.
  static M3Texture createSampleCubemap({int gridCount = 8}) {
    M3Texture tex = M3Texture(target: WebGL.TEXTURE_CUBE_MAP);
    tex.name = 'sample_cubemap';

    List<Vector4> colors = [
      Vector4(0.8, 0.3, 0.3, 1),
      Vector4(0.6, 0.4, 0.4, 1),
      Vector4(0.3, 0.8, 0.3, 1),
      Vector4(0.2, 0.5, 0.2, 1),
      Vector4(0.3, 0.3, 0.8, 1),
      Vector4(0.4, 0.4, 0.6, 1),
    ];

    for (int i = 0; i < 6; i++) {
      tex._initCheckerboard(
        gridCount,
        colors[i],
        i % 2 == 0 ? Vector4(0.6, 0.6, 0.6, 1) : Vector4(0.3, 0.3, 0.3, 1),
        faceTarget: _cubeMapFaceTargets[i],
      );
    }
    tex.generateMipmap();
    return tex;
  }

  /// Load a texture from the given URL.
  static Future<M3Texture> loadTexture(String url) async {
    M3Texture tex = M3Texture(useMipmaps: false);
    tex.name = url;
    await tex._loadTarget(url);

    M3Log.i('M3Texture', tex.toString());
    return tex;
  }

  static Future<M3Texture> loadCubemap(
    String urlPosX,
    String urlNegX,
    String urlPosY,
    String urlNegY,
    String urlPosZ,
    String urlNegZ,
  ) async {
    M3Texture tex = M3Texture(target: WebGL.TEXTURE_CUBE_MAP);
    List<String> urls = [urlPosX, urlNegX, urlPosY, urlNegY, urlPosZ, urlNegZ];

    // 6 faces for cubemap
    for (int i = 0; i < 6; i++) {
      await tex._loadTarget(urls[i], faceTarget: _cubeMapFaceTargets[i]);
      M3Log.i('M3Texture', tex.toString());
    }
    tex.generateMipmap();
    tex.unbind();
    return tex;
  }

  /// Create a texture from bytes.
  static Future<M3Texture> createFromBytes(Uint8List bytes, String name) async {
    M3Texture tex = M3Texture();
    tex.name = name;

    final img = await M3ResourceManager.createImageFromBytes(bytes);
    await tex.loadTargetFromImage(img);
    tex.generateMipmap();
    M3Log.i('M3Texture', tex.toString());
    return tex;
  }

  Future<void> _loadTarget(String url, {int faceTarget = WebGL.TEXTURE_2D}) async {
    final filename = url;
    if (!await M3ResourceManager.isAssetExists(filename)) {
      M3Log.e('M3Texture', 'assets: $filename');
      _initCheckerboard(8, Vector4(0.9, 0.2, 0.1, 1), Vector4(0.7, 0.6, 0.5, 1), faceTarget: faceTarget);
      return;
    }

    final lowerName = filename.toLowerCase();
    name = filename;

    if (lowerName.endsWith('.ktx') || lowerName.endsWith('.ktx2') || lowerName.endsWith('.astc')) {
      // KTX compressed texture: ASTC
      final ktxInfo = await KtxInfo.parseKtx(filename);
      name = filename;
      texW = ktxInfo.width;
      texH = ktxInfo.height;
      Uint8List byteData = ktxInfo.texData;

      final pixelFormat = ktxInfo.glFormat;
      if (kIsWeb) {
        if (!PlatformInfo.enableWebGLExtension('WEBGL_compressed_texture_astc')) {
          M3Log.w('M3Texture', 'ASTC extension NOT SUPPORTED, use checkerboard instead');
          _initCheckerboard(8, Vector4(1.0, 0.3, 0.1, 1), Vector4(0.7, 0.1, 0.0, 1), faceTarget: faceTarget);
          return;
        }
      }

      gl.compressedTexImage2D(faceTarget, 0, pixelFormat, texW, texH, 0, byteData);
      // } else if (lowerName.endsWith('.pvr')) {
      // PVR compressed texture
    } else {
      final img = await M3ResourceManager.loadImage(filename);
      await loadTargetFromImage(img, faceTarget: faceTarget);
    }
  }

  Future<void> loadTargetFromImage(ui.Image image, {int faceTarget = WebGL.TEXTURE_2D}) async {
    texW = image.width;
    texH = image.height;

    final pixelFormat = WebGL.RGBA;
    // Macbear note: texImage2DfromImage not working on web
    // await gl.texImage2DfromImage(
    //   faceTarget,
    //   image,
    //   format: pixelFormat,
    //   internalformat: pixelFormat,
    //   type: WebGL.UNSIGNED_BYTE,
    // );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      M3Log.e('M3Texture', 'M3Texture.toByteData returned null');
      return;
    }
    final pixels = byteData.buffer.asUint8List();

    gl.texImage2D(faceTarget, 0, pixelFormat, texW, texH, 0, pixelFormat, WebGL.UNSIGNED_BYTE, toU8List(pixels));
  }

  /// Create a procedural water normal map texture of a specified size and strength.
  static M3Texture createWaterNormalMap({int size = 256, double strength = 5.0}) {
    M3Texture tex = M3Texture(useMipmaps: true);
    tex.name = "procedural_water_normal";
    tex.texW = size;
    tex.texH = size;

    final data = Uint8List(size * size * 4);
    final p = List<int>.filled(512, 0);
    for (int i = 0; i < 256; i++) {
      p[i] = p[i + 256] = M3Constants.permutation[i];
    }

    double fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);
    double lerp(double t, double a, double b) => a + t * (b - a);
    double grad(int hash, double x, double y) {
      int h = hash & 15;
      double u = h < 8 ? x : y;
      double v = h < 4 ? y : (h == 12 || h == 14 ? x : 0.0);
      return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
    }

    // Custom 2D tiling noise that wraps at the given integer period.
    double tilingNoise(double x, double y, int period) {
      final int prd = period.clamp(1, 256);

      int intX = x.floor();
      int intY = y.floor();

      double xf = x - intX;
      double yf = y - intY;

      int x0 = intX % prd;
      if (x0 < 0) x0 += prd;
      int x1 = (x0 + 1) % prd;

      int y0 = intY % prd;
      if (y0 < 0) y0 += prd;
      int y1 = (y0 + 1) % prd;

      double u = fade(xf);
      double v = fade(yf);

      int a0 = p[x0] + y0;
      int a1 = p[x0] + y1;
      int b0 = p[x1] + y0;
      int b1 = p[x1] + y1;

      int aa = p[a0];
      int ab = p[a1];
      int ba = p[b0];
      int bb = p[b1];

      return lerp(
        v,
        lerp(u, grad(aa, xf, yf), grad(ba, xf - 1, yf)),
        lerp(u, grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1)),
      );
    }

    // Height function helper that wraps periodically on [0, 1]
    double getWarpedHeight(double u, double v) {
      double wrapU = u % 1.0;
      double wrapV = v % 1.0;
      if (wrapU < 0.0) wrapU += 1.0;
      if (wrapV < 0.0) wrapV += 1.0;

      // 1. Domain warping: perturb coordinates using low-frequency Perlin noise.
      final double dx =
          tilingNoise(wrapU * 4.0 + 1.2, wrapV * 4.0 + 3.4, 4) * 0.15 +
          tilingNoise(wrapU * 8.0 + 5.6, wrapV * 8.0 + 7.8, 8) * 0.07;
      final double dy =
          tilingNoise(wrapU * 4.0 + 9.1, wrapV * 4.0 + 2.3, 4) * 0.15 +
          tilingNoise(wrapU * 8.0 + 4.5, wrapV * 8.0 + 6.7, 8) * 0.07;

      final double warpedU = wrapU + dx;
      final double warpedV = wrapV + dy;

      // 2. Ridged noise: sum multiple octaves for crisp, organic ripple peaks
      double h = 0.0;
      double amp = 1.0;
      int period = 6;
      double maxAmp = 0.0;

      for (int i = 0; i < 4; i++) {
        final double n = tilingNoise(warpedU * period, warpedV * period, period);
        final double ridge = 1.0 - n.abs();
        h += ridge * ridge * amp;
        maxAmp += amp;
        period *= 2;
        amp *= 0.5;
      }
      h /= maxAmp;

      // 3. High-frequency micro-noise for extra detail/texture
      final double micro =
          tilingNoise(wrapU * 64.0, wrapV * 64.0, 64) * 0.05 +
          tilingNoise(wrapU * 128.0 + 0.5, wrapV * 128.0 + 0.5, 128) * 0.025;
      h += micro;

      return h;
    }

    final double eps = 1.0 / size;

    for (int y = 0; y < size; y++) {
      final double v = y / size;
      for (int x = 0; x < size; x++) {
        final double u = x / size;

        // Sample heights at center, right, and down to compute numerical derivatives
        final double hCenter = getWarpedHeight(u, v);
        final double hRight = getWarpedHeight(u + eps, v);
        final double hDown = getWarpedHeight(u, v + eps);

        // Compute derivatives scaled by the strength multiplier
        final double dhdu = (hRight - hCenter) * strength;
        final double dhdv = (hDown - hCenter) * strength;

        // Normal vector in tangent space: N = (-dh/du, -dh/dv, 1.0)
        double nx = -dhdu;
        double ny = -dhdv;
        double nz = 1.0;

        // Normalize to get unit length
        final double len = sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;

        // Map from [-1.0, 1.0] to [0, 255]
        final int r = ((nx + 1.0) * 127.5).round().clamp(0, 255);
        final int g = ((ny + 1.0) * 127.5).round().clamp(0, 255);
        final int b = ((nz + 1.0) * 127.5).round().clamp(0, 255);

        final int idx = (y * size + x) * 4;
        data[idx] = r;
        data[idx + 1] = g;
        data[idx + 2] = b;
        data[idx + 3] = 255;
      }
    }

    tex.bind();
    tex.gl.texImage2D(WebGL.TEXTURE_2D, 0, WebGL.RGBA, size, size, 0, WebGL.RGBA, WebGL.UNSIGNED_BYTE, toU8List(data));
    tex.generateMipmap();
    return tex;
  }

  /// Create a wood texture with specified size.
  static Future<M3Texture> createWoodTexture({int size = 512}) async {
    M3Texture tex = M3Texture();
    final img = await _generateWoodImage(size: size);
    await tex.loadTargetFromImage(img);
    tex.generateMipmap();
    return tex;
  }

  // 生成高品質木紋紋理 (Advanced Procedural Wood)
  static Future<ui.Image> _generateWoodImage({int size = 512}) async {
    final Uint8List pixels = Uint8List(size * size * 4);

    // 核心噪點函數 (Deterministic Hash)
    double noise(double x, double y) {
      int n = (x.toInt() * 12345 + y.toInt() * 67890);
      n = (n << 13) ^ n;
      return (1.0 - ((n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff) / 1073741824.0);
    }

    // 平滑插值噪點
    double smoothNoise(double x, double y) {
      double corners = (noise(x - 1, y - 1) + noise(x + 1, y - 1) + noise(x - 1, y + 1) + noise(x + 1, y + 1)) / 16;
      double sides = (noise(x - 1, y) + noise(x + 1, y) + noise(x, y - 1) + noise(x, y + 1)) / 8;
      double center = noise(x, y) / 4;
      return corners + sides + center;
    }

    // 擾動 (Turbulence)
    double getTurbulence(double x, double y, double size) {
      double value = 0.0, initialSize = size;
      while (size >= 1) {
        value += smoothNoise(x / size, y / size) * size;
        size /= 2;
      }
      return (128.0 * value / initialSize);
    }

    // Wood Colors (更好的木質感配色)
    final colBase = [160, 110, 60]; // 中等木色
    final colDark = [70, 35, 10]; // 深色紋路
    final colLight = [200, 160, 110]; // 亮部

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        double nx = x.toDouble();
        double ny = y.toDouble();

        // 1. 取得擾動值
        double turb = getTurbulence(nx, ny, 64.0);

        // 2. 核心紋路邏輯：歪斜的 Sine 波
        // 模擬木材縱向生長，增加橫向的隨機偏移
        double dist = (nx * 0.1) + (ny * 0.02) + (turb * 0.1);
        double val = (sin(dist * pi * 0.2) + 1.0) / 2.0;

        // 3. 調整曲線讓紋路更銳利一點
        val = pow(val, 0.5).toDouble();

        // 4. 三色插值
        double r, g, b;
        if (val < 0.5) {
          double t = val * 2.0;
          r = colDark[0] * (1 - t) + colBase[0] * t;
          g = colDark[1] * (1 - t) + colBase[1] * t;
          b = colDark[2] * (1 - t) + colBase[2] * t;
        } else {
          double t = (val - 0.5) * 2.0;
          r = colBase[0] * (1 - t) + colLight[0] * t;
          g = colBase[1] * (1 - t) + colLight[1] * t;
          b = colBase[2] * (1 - t) + colLight[2] * t;
        }

        // 5. 疊加垂直導管 (Pores) 與表面細紋
        double pores = smoothNoise(nx * 5, ny * 0.2);
        if (pores > 0.7) {
          double pVal = (pores - 0.7) * 2.0;
          r *= (1.0 - pVal * 0.3);
          g *= (1.0 - pVal * 0.3);
          b *= (1.0 - pVal * 0.3);
        }

        // 6. 微觀隨機噪點
        double grain = 1.0 + (noise(nx, ny) * 0.03);
        r *= grain;
        g *= grain;
        b *= grain;

        final int index = (y * size + x) * 4;
        pixels[index] = r.toInt().clamp(0, 255);
        pixels[index + 1] = g.toInt().clamp(0, 255);
        pixels[index + 2] = b.toInt().clamp(0, 255);
        pixels[index + 3] = 255;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.rgba8888, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  /// debug draw on screen
  void debugDraw(double x, double y, double scaleX, double scaleY) {
    final Matrix4 mat = Matrix4.compose(Vector3(x, y, 0.0), Quaternion.identity(), Vector3(scaleX, scaleY, 1.0));
    M3Shape2D.drawImage(this, mat);
  }
}
