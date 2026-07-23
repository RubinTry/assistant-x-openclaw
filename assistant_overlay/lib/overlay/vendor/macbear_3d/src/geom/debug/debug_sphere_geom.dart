part of '../geom.dart';

/// A wireframe sphere geometry for visualizing bounding volumes.
///
/// Displays three circular rings along the XY, XZ, and YZ planes.
class M3DebugSphereGeom extends M3Geom {
  M3DebugSphereGeom({double radius = 1.0}) {
    int segments = 24; // must be even value
    // initialize
    _init(vertexCount: (segments + 1) * 3);
    name = "DebugSphere";

    // vertices
    final vertices = _vertices!;
    for (int j = 0; j < 3; j++) {
      for (int i = 0; i <= segments; i++) {
        final angle = i * pi * 2 / segments;
        double x = cos(angle) * radius;
        double y = sin(angle) * radius;
        double z = 0.0;
        if (j == 1) {
          z = x;
          x = 0.0;
        } else if (j == 2) {
          z = y;
          y = 0.0;
        }
        vertices[i + j * (segments + 1)] = Vector3(x, y, z);
      }
    }

    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = radius;

    // solid faces: only outline
    for (int j = 0; j < 3; j++) {
      final indices = Uint16List(segments + 1);
      final index = j * (segments + 1);
      for (int i = 0; i <= segments; i++) {
        indices[i] = index + i;
      }
      _faceIndices.add(_M3Indices(WebGL.LINE_STRIP, indices));
    }

    // none wireframe edges
  }
}
