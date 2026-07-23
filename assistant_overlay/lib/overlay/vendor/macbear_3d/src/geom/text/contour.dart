part of '../geom.dart';

class M3Contour {
  final List<M3ContourInfo> infos = [];
  final List<List<Vector2>> normalizedOuters = [];
  final List<List<Vector2>> normalizedHoles = [];
  final List<int> outerOrigIndices = [];
  final List<int> holeOrigIndices = [];

  M3Contour(List<List<Vector2>> contours) {
    if (contours.isEmpty) return;

    // 1. Calculate signed areas and wrap in infos
    List<Map<String, dynamic>> contourData = contours.where((c) => c.length >= 3).map((c) {
      double area = _getSignedArea(c);
      return {'points': c, 'area': area};
    }).toList();

    if (contourData.isEmpty) return;

    // Largest contour first
    contourData.sort((a, b) => (b['area'] as double).abs().compareTo((a['area'] as double).abs()));

    for (int i = 0; i < contourData.length; i++) {
      var data = contourData[i];
      infos.add(M3ContourInfo(data['points'] as List<Vector2>, data['area'] as double, i));
    }

    // 2. Determine hierarchy (nesting)
    for (int i = 0; i < infos.length; i++) {
      var c = infos[i];
      for (int j = 0; j < infos.length; j++) {
        if (i == j) continue;
        var container = infos[j];
        if (_isContourInside(c.points, container.points)) {
          if (c.parent == null || container.area.abs() < c.parent!.area.abs()) {
            c.parent = container;
          }
        }
      }
    }

    // 3. Classify: Hole if inside container with opposite sign
    for (var info in infos) {
      bool isHole = (info.parent != null && info.area.sign != info.parent!.area.sign);
      List<Vector2> pts = List.from(info.points);

      if (isHole) {
        if (info.area > 0) pts = pts.reversed.toList();
        normalizedHoles.add(pts);
        holeOrigIndices.add(info.index);
      } else {
        if (info.area < 0) pts = pts.reversed.toList();
        normalizedOuters.add(pts);
        outerOrigIndices.add(info.index);
      }
    }
  }

  static double _getSignedArea(List<Vector2> contour) {
    double area = 0.0;
    for (int k = 0; k < contour.length; k++) {
      Vector2 p1 = contour[k];
      Vector2 p2 = contour[(k + 1) % contour.length];
      area += (p1.x * p2.y - p2.x * p1.y);
    }
    return area / 2.0;
  }

  static bool _isPointInPolygon(Vector2 p, List<Vector2> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].y > p.y) != (polygon[j].y > p.y)) &&
          (p.x < (polygon[j].x - polygon[i].x) * (p.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _isContourInside(List<Vector2> inner, List<Vector2> outer) {
    for (var p in inner) {
      if (!_isPointInPolygon(p, outer)) return false;
    }
    return true;
  }
}

class M3ContourInfo {
  final List<Vector2> points;
  final double area;
  final int index;
  M3ContourInfo? parent;
  M3ContourInfo(this.points, this.area, this.index);
}
