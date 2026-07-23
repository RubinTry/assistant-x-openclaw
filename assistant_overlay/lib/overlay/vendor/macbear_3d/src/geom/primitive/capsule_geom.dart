part of '../geom.dart';

/// A capsule geometry with hemispherical caps and a cylindrical body.
///
/// Vertices are ordered from top to bottom, counter-clockwise by each row.
class M3CapsuleGeom extends M3Geom {
  M3CapsuleGeom(
    double radius,
    double height, {
    int radiusSegments = M3Geom.radialSegments,
    int heightSegments = 1,
    int capSegments = 8,
    M3Axis axis = M3Axis.z,
  }) {
    radiusSegments = min(max(radiusSegments, 3), 64);
    heightSegments = min(max(heightSegments, 1), 64);
    capSegments = min(max(capSegments, 2), 32);

    name = "Capsule";

    // Total rings = capSegments (top) + heightSegments (middle) + capSegments (bottom) + 1
    int totalRings = capSegments * 2 + heightSegments + 1;
    int numVert = (radiusSegments + 1) * totalRings;

    _init(vertexCount: numVert, withNormals: true, withUV: true);

    final vertices = _vertices!;
    final normals = _normals!;
    final uvs = _uvs!;
    final halfHeight = height * 0.5;

    final rot = Matrix3.identity();
    if (axis == M3Axis.x) {
      rot.setRotationY(pi / 2);
    } else if (axis == M3Axis.y) {
      rot.setRotationX(-pi / 2);
    }

    Vector3 transform(double cx, double cy, double h) {
      final v = Vector3(cx, cy, h);
      if (axis != M3Axis.z) {
        rot.transform(v);
      }
      return v;
    }

    int index = 0;
    for (int i = 0; i < totalRings; i++) {
      double h, ringRadius, phi;

      if (i <= capSegments) {
        // Top cap (phi from 0 to pi/2)
        phi = (pi * 0.5) * (i / capSegments);
        h = halfHeight + radius * cos(phi);
        ringRadius = radius * sin(phi);
      } else if (i <= capSegments + heightSegments) {
        // Cylindrical part
        h = halfHeight - height * ((i - capSegments) / heightSegments);
        ringRadius = radius;
      } else {
        // Bottom cap (phi from pi/2 to pi)
        phi = (pi * 0.5) + (pi * 0.5) * ((i - (capSegments + heightSegments)) / capSegments);
        h = -halfHeight + radius * cos(phi);
        ringRadius = radius * sin(phi);
      }

      double ratioB = i / (totalRings - 1);

      for (int j = 0; j <= radiusSegments; j++) {
        double ratioA = j / radiusSegments;
        double angleA = pi * 2 * ratioA;
        double x = ringRadius * cos(angleA);
        double y = ringRadius * sin(angleA);

        vertices[index] = transform(x, y, h);

        // Normal calculation
        if (i < capSegments) {
          normals[index] = transform(x, y, h - halfHeight).normalized();
        } else if (i > capSegments + heightSegments) {
          normals[index] = transform(x, y, h + halfHeight).normalized();
        } else {
          // Cylindrical part or equator rings
          normals[index] = transform(cos(angleA), sin(angleA), 0);
        }

        uvs[index] = Vector2(ratioA, 1.0 - ratioB);
        index++;
      }
    }

    _createVBO();
    localBounding.sphere.radius = radius + halfHeight;

    // solid: triangle-strip
    int numIndex = (radiusSegments + 1) * 2 * (totalRings - 1);
    Uint16List indices = Uint16List(numIndex);
    index = 0;

    for (int i = 0; i < totalRings - 1; i++) {
      int startVert = (radiusSegments + 1) * i;
      for (int j = 0; j <= radiusSegments; j++) {
        indices[index] = startVert + j;
        indices[index + 1] = indices[index] + (radiusSegments + 1);
        index += 2;
      }
    }
    _faceIndices.add(_M3Indices(WebGL.TRIANGLE_STRIP, indices));

    // wireframe edges (horizontal rings + vertical slices)
    List<int> wireIndices = [];
    // Horizontal rings
    for (int i = 0; i < totalRings; i++) {
      int rowStart = i * (radiusSegments + 1);
      for (int j = 0; j < radiusSegments; j++) {
        wireIndices.add(rowStart + j);
        wireIndices.add(rowStart + j + 1);
      }
    }
    // Vertical slices
    for (int j = 0; j < radiusSegments; j++) {
      for (int i = 0; i < totalRings - 1; i++) {
        int rowStart = i * (radiusSegments + 1);
        wireIndices.add(rowStart + j);
        wireIndices.add(rowStart + (radiusSegments + 1) + j);
      }
    }
    _edgeIndices.add(_M3Indices(WebGL.LINES, Uint16List.fromList(wireIndices)));
  }
}
