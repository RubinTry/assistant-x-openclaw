part of '../geom.dart';

/// A cylinder or cone geometry with configurable top and bottom radii.
///
/// Vertices are ordered from top to bottom, counter-clockwise by each row.
/// Set [topRadius] to 0 for a cone shape.
class M3CylinderGeom extends M3Geom {
  M3CylinderGeom(
    double topRadius,
    double bottomRadius,
    double height, {
    int radiusSegments = M3Geom.radialSegments,
    int heightSegments = 1,
    double creaseAngle = 40.0,
    M3Axis axis = M3Axis.z,
  }) {
    radiusSegments = min(max(radiusSegments, 3), 64);
    heightSegments = min(max(heightSegments, 1), 64);
    final bool smooth = (360.0 / radiusSegments) <= creaseAngle;

    name = "Cylinder";

    List<Vector3> allVertices = [];
    List<Vector3> allNormals = [];
    List<Vector2> allUvs = [];
    List<int> faceIndices = [];
    List<int> wireIndices = [];

    double cotan = (bottomRadius - topRadius) / height;

    if (smooth) {
      // 1. Smooth Side (Shared Vertices)
      for (int i = 0; i <= heightSegments; i++) {
        final ratio = i / heightSegments;
        final radius = topRadius * (1.0 - ratio) + bottomRadius * ratio;
        double z = height * (0.5 - ratio);
        for (int j = 0; j <= radiusSegments; j++) {
          double ratioA = j / radiusSegments;
          double angleA = pi * 2 * ratioA;
          double x = cos(angleA);
          double y = sin(angleA);
          allVertices.add(Vector3(radius * x, radius * y, z));
          allNormals.add(Vector3(x, y, cotan).normalized());
          allUvs.add(Vector2(ratioA, (1.0 - ratio) * 0.5));
        }
      }

      // 1b. Smooth Side Indices (using TRIANGLE_STRIP)
      List<int> sideStripIndices = [];
      for (int i = 0; i < heightSegments; i++) {
        int rowStart = i * (radiusSegments + 1);
        int nextRowStart = (i + 1) * (radiusSegments + 1);
        for (int j = 0; j <= radiusSegments; j++) {
          sideStripIndices.add(rowStart + j);
          sideStripIndices.add(nextRowStart + j);
        }
        // Add a separate entry for each strip to avoid connective triangles between height segments
        _faceIndices.add(_M3Indices(WebGL.TRIANGLE_STRIP, Uint16List.fromList(sideStripIndices)));
        sideStripIndices = [];
      }

      // Smooth Side Wireframe
      for (int i = 0; i < heightSegments; i++) {
        int rowStart = i * (radiusSegments + 1);
        int nextRowStart = (i + 1) * (radiusSegments + 1);
        for (int j = 0; j < radiusSegments; j++) {
          int i0 = rowStart + j;
          int i1 = nextRowStart + j;
          int i2 = nextRowStart + j + 1;
          int i3 = rowStart + j + 1;
          wireIndices.addAll([i0, i1, i1, i2, i2, i3, i3, i0]);
        }
      }
    } else {
      // 2. Flat Side (Unique Vertices per Face)
      for (int i = 0; i < heightSegments; i++) {
        final r1 = i / heightSegments;
        final r2 = (i + 1) / heightSegments;
        final radius1 = topRadius * (1.0 - r1) + bottomRadius * r1;
        final radius2 = topRadius * (1.0 - r2) + bottomRadius * r2;
        double z1 = height * (0.5 - r1);
        double z2 = height * (0.5 - r2);

        for (int j = 0; j < radiusSegments; j++) {
          double a1 = pi * 2 * j / radiusSegments;
          double a2 = pi * 2 * (j + 1) / radiusSegments;
          double midA = (a1 + a2) * 0.5;

          Vector3 n = Vector3(cos(midA), sin(midA), cotan).normalized();
          int base = allVertices.length;

          // Quad vertices
          allVertices.add(Vector3(radius1 * cos(a1), radius1 * sin(a1), z1));
          allVertices.add(Vector3(radius2 * cos(a1), radius2 * sin(a1), z2));
          allVertices.add(Vector3(radius2 * cos(a2), radius2 * sin(a2), z2));
          allVertices.add(Vector3(radius1 * cos(a2), radius1 * sin(a2), z1));

          allNormals.addAll([n, n, n, n]);

          allUvs.add(Vector2(j / radiusSegments, (1.0 - r1) * 0.5));
          allUvs.add(Vector2(j / radiusSegments, (1.0 - r2) * 0.5));
          allUvs.add(Vector2((j + 1) / radiusSegments, (1.0 - r2) * 0.5));
          allUvs.add(Vector2((j + 1) / radiusSegments, (1.0 - r1) * 0.5));

          faceIndices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
          wireIndices.addAll([base, base + 1, base + 1, base + 2, base + 2, base + 3, base + 3, base]);
        }
      }
    }

    // 3. Caps
    for (int i = 0; i < 2; i++) {
      final fDir = (i != 0) ? -1.0 : 1.0;
      final radius = (i != 0) ? bottomRadius : topRadius;
      final uvZero = Vector2(0.25 + i * 0.5, 0.75);
      int capBase = allVertices.length;

      for (int j = 0; j < radiusSegments; j++) {
        final angleA = pi * 2 * j / radiusSegments;
        double x = cos(angleA);
        double y = sin(angleA);

        allVertices.add(Vector3(x * radius, y * radius, height * 0.5 * fDir));
        allNormals.add(Vector3(0, 0, fDir));
        allUvs.add(Vector2(x, y) * 0.25 + uvZero);
      }

      // Cap indices (TRIANGLES)
      for (int j = 0; j < radiusSegments - 2; j++) {
        int next1 = 1, next2 = 2;
        if (i != 0) {
          next1 = 2;
          next2 = 1;
        }
        faceIndices.addAll([capBase, capBase + j + next1, capBase + j + next2]);
      }
      // Cap wire
      for (int j = 0; j < radiusSegments; j++) {
        wireIndices.addAll([capBase + j, capBase + (j + 1) % radiusSegments]);
      }
    }

    // Initialize buffers
    _init(vertexCount: allVertices.length, withNormals: true, withUV: true);

    final rot = Matrix3.identity();
    if (axis == M3Axis.x) {
      rot.setRotationY(pi / 2);
    } else if (axis == M3Axis.y) {
      rot.setRotationX(-pi / 2);
    }

    for (int i = 0; i < allVertices.length; i++) {
      if (axis != M3Axis.z) {
        rot.transform(allVertices[i]);
        rot.transform(allNormals[i]);
      }
      _vertices![i] = allVertices[i];
      _normals![i] = allNormals[i];
      _uvs![i] = allUvs[i];
    }

    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = Vector2(max(topRadius, bottomRadius), height / 2).length;

    // Add collected TRIANGLES (caps and/or flat side)
    if (faceIndices.isNotEmpty) {
      _faceIndices.add(_M3Indices(WebGL.TRIANGLES, Uint16List.fromList(faceIndices)));
    }

    // wireframe edges
    _edgeIndices.add(_M3Indices(WebGL.LINES, Uint16List.fromList(wireIndices)));
  }
}
