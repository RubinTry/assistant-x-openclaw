// Macbear3D engine
import 'constants.dart';

/// Utility class for procedural noise generation.
class M3Noise {
  static final List<int> _p = List.generate(512, (i) => 0);
  static bool _init = false;

  static void _ensureInit() {
    if (_init) return;
    for (int i = 0; i < 256; i++) {
      _p[i] = _p[i + 256] = M3Constants.permutation[i];
    }
    _init = true;
  }

  static double fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);
  static double lerp(double t, double a, double b) => a + t * (b - a);
  static double grad(int hash, double x, double y, double z) {
    int h = hash & 15;
    double u = h < 8 ? x : y;
    double v = h < 4
        ? y
        : h == 12 || h == 14
        ? x
        : z;
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
  }

  /// 2D Perlin noise
  static double perlin2D(double x, double y) {
    _ensureInit();
    int X = x.floor() & 255;
    int Y = y.floor() & 255;
    x -= x.floor();
    y -= y.floor();
    double u = fade(x);
    double v = fade(y);
    int a = _p[X] + Y, aa = _p[a], ab = _p[a + 1];
    int b = _p[X + 1] + Y, ba = _p[b], bb = _p[b + 1];

    return lerp(
      v,
      lerp(u, grad(_p[aa], x, y, 0), grad(_p[ba], x - 1, y, 0)),
      lerp(u, grad(_p[ab], x, y - 1, 0), grad(_p[bb], x - 1, y - 1, 0)),
    );
  }

  /// Fractal Brownian Motion (fBm)
  static double fBm(double x, double y, {int octaves = 6, double persistence = 0.5}) {
    double total = 0;
    double frequency = 1;
    double amplitude = 1;
    double maxValue = 0;
    for (int i = 0; i < octaves; i++) {
      total += perlin2D(x * frequency, y * frequency) * amplitude;
      maxValue += amplitude;
      amplitude *= persistence;
      frequency *= 2;
    }
    return (total / maxValue + 1.0) / 2.0; // normalize to 0~1
  }
}
