import 'package:vector_math/vector_math.dart';

/// A polygon triangulation class using the Ear Clipping algorithm.
///
/// Supports simple polygons and polygons with holes.
class M3EarClipping {
  /// Triangulates a polygon defined by [vertices].
  ///
  /// [holes] is a list of hole contours.
  /// Returns a record contains the processed [vertices] and triangulation [indices].
  static ({List<Vector2> vertices, List<int> indices}) triangulate(
    List<Vector2> vertices, {
    List<List<Vector2>>? holes,
  }) {
    List<Vector2> data = List.from(vertices);

    // Remove duplicate consecutive vertices
    void removeDuplicates(List<Vector2> pts) {
      for (int i = 0; i < pts.length; i++) {
        if (pts[i].distanceToSquared(pts[(i + 1) % pts.length]) < 1e-10) {
          pts.removeAt(i);
          i--;
        }
      }
    }

    removeDuplicates(data);

    if (holes != null && holes.isNotEmpty) {
      // Deep copy holes
      List<List<Vector2>> holesCopy = holes.map((h) {
        var hc = List<Vector2>.from(h);
        removeDuplicates(hc);
        return hc;
      }).toList();
      _eliminateHoles(data, holesCopy);
    }

    if (data.length < 3) return (vertices: data, indices: []);

    List<int> indices = List.generate(data.length, (i) => i);
    List<int> result = [];

    int count = indices.length;
    int prevCount = 0;

    int i = 0;
    while (count > 3) {
      if (i >= count) {
        if (count == prevCount) {
          // Break to avoid infinite loop
          break;
        }
        prevCount = count;
        i = 0;
      }

      int i0 = indices[i];
      int i1 = indices[(i + 1) % count];
      int i2 = indices[(i + 2) % count];

      if (_isEar(data, i0, i1, i2, indices)) {
        result.add(i0);
        result.add(i1);
        result.add(i2);
        indices.removeAt((i + 1) % count);
        count--;
        i = 0; // Restart search
      } else {
        i++;
      }
    }

    if (count == 3) {
      result.add(indices[0]);
      result.add(indices[1]);
      result.add(indices[2]);
    }

    return (vertices: data, indices: result);
  }

  // --- Helper methods ---

  static bool _isEar(List<Vector2> vertices, int i0, int i1, int i2, List<int> indices) {
    Vector2 a = vertices[i0];
    Vector2 b = vertices[i1];
    Vector2 c = vertices[i2];

    // 1. Check if reflex (convex angle)
    // Cross product > 0 for CCW.
    // (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    double cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (cross <= 1e-10) return false; // fast fail if not convex or collinear

    // 2. Check if any other point is inside this triangle
    // It's an ear if no other vertex is inside the triangle abc
    for (int idx in indices) {
      if (idx == i0 || idx == i1 || idx == i2) continue;
      Vector2 p = vertices[idx];
      // Skip points that are at the same location as the triangle vertices
      if (p.distanceToSquared(a) < 1e-10 || p.distanceToSquared(b) < 1e-10 || p.distanceToSquared(c) < 1e-10) continue;

      if (_isPointInTriangle(p, a, b, c)) {
        return false;
      }
    }
    return true;
  }

  static bool _isPointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c) {
    // Barycentric coordinates technique or similar
    double v0x = c.x - a.x;
    double v0y = c.y - a.y;
    double v1x = b.x - a.x;
    double v1y = b.y - a.y;
    double v2x = p.x - a.x;
    double v2y = p.y - a.y;

    double dot00 = v0x * v0x + v0y * v0y;
    double dot01 = v0x * v1x + v0y * v1y;
    double dot02 = v0x * v2x + v0y * v2y;
    double dot11 = v1x * v1x + v1y * v1y;
    double dot12 = v1x * v2x + v1y * v2y;

    double invDenom = 1 / (dot00 * dot11 - dot01 * dot01);
    double u = (dot11 * dot02 - dot01 * dot12) * invDenom;
    double v = (dot00 * dot12 - dot01 * dot02) * invDenom;

    const double eps = -1e-10;
    return (u >= eps) && (v >= eps) && (u + v < 1.0 - eps);
  }

  // Very basic hole elimination: finding the mutually visible connection
  // and cutting the hole to merge into outer polygon.
  // This is a simplified version.
  static void _eliminateHoles(List<Vector2> outer, List<List<Vector2>> holes) {
    // Sort holes by max X descending to process rightmost holes first
    // and minimize the chance of bridge segments crossing other holes.
    List<({List<Vector2> pts, double maxX})> sortedHoles = holes.map((h) {
      double mx = -double.infinity;
      for (var p in h) {
        if (p.x > mx) mx = p.x;
      }
      return (pts: h, maxX: mx);
    }).toList();
    sortedHoles.sort((a, b) => b.maxX.compareTo(a.maxX));

    for (var hData in sortedHoles) {
      List<Vector2> hole = hData.pts;
      int holeMaxXIdx = 0;
      double maxX = -double.infinity;
      for (int i = 0; i < hole.length; i++) {
        if (hole[i].x > maxX) {
          maxX = hole[i].x;
          holeMaxXIdx = i;
        }
      }

      Vector2 holePt = hole[holeMaxXIdx];

      // Find the best bridge point on the outer polygon.
      // We look for a vertex that is to the right of holePt and minimizes distance.
      int bestIdx = -1;
      double bestDist = double.infinity;

      for (int i = 0; i < outer.length; i++) {
        // Only consider vertices to the right (or same X) to minimize overlap
        if (outer[i].x >= holePt.x) {
          double dsq = outer[i].distanceToSquared(holePt);
          if (dsq < bestDist) {
            bestDist = dsq;
            bestIdx = i;
          }
        }
      }

      // If no points to the right, just pick the closest point regardless
      if (bestIdx == -1) {
        for (int i = 0; i < outer.length; i++) {
          double dsq = outer[i].distanceToSquared(holePt);
          if (dsq < bestDist) {
            bestDist = dsq;
            bestIdx = i;
          }
        }
      }

      if (bestIdx != -1) {
        // Rotate hole so holeMaxXIdx is first
        List<Vector2> rotatedHole = [];
        for (int k = 0; k < hole.length; k++) {
          rotatedHole.add(hole[(holeMaxXIdx + k) % hole.length]);
        }

        List<Vector2> newOuter = [];
        newOuter.addAll(outer.sublist(0, bestIdx + 1));
        newOuter.addAll(rotatedHole);
        newOuter.add(rotatedHole[0]); // close hole
        newOuter.add(outer[bestIdx]); // bridge back to outer
        newOuter.addAll(outer.sublist(bestIdx + 1));

        outer.clear();
        outer.addAll(newOuter);
      }
    }
  }
}
