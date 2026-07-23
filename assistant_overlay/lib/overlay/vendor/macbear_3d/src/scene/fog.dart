// Macbear3D engine
import '../m3_internal.dart';

/// Configures fog settings for a 3D scene.
class M3Fog {
  // standard sphere fog by camera (origin)
  Vector3 color = M3Constants.colorSkyBlue.clone();
  double start = 90.0;
  double depth = 10.0; // 0 - no sphere fog

  // plane fog: usually horizon fog for water
  Vector3 planeColor = M3Constants.colorOcean.clone();
  double planeHeight = 0.0; // 0 - no plane fog
  Plane plane = Plane()..setFromComponents(0, 0, 1, 0);

  M3Fog();

  void setFrom(M3Fog other) {
    // standard sphere fog
    color.setFrom(other.color);
    start = other.start;
    depth = other.depth;

    // plane fog: usually horizon fog for water
    planeColor.setFrom(other.planeColor);
    planeHeight = other.planeHeight;
    plane.normal.x = other.plane.normal.x;
    plane.normal.y = other.plane.normal.y;
    plane.normal.z = other.plane.normal.z;
    plane.constant = other.plane.constant;
  }
}
