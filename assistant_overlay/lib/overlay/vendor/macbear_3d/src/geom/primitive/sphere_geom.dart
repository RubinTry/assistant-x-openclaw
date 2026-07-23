part of '../geom.dart';

/// A UV sphere geometry with configurable radius and segment count.
///
/// Vertices are ordered from top to bottom, counter-clockwise by each row.
class M3SphereGeom extends M3Geom {
  M3SphereGeom(double radius, {int widthSegments = M3Geom.radialSegments, int heightSegments = 8}) {
    widthSegments = min(max(widthSegments, 3), 64);
    heightSegments = min(max(heightSegments, 2), 32);
    int numVert = (widthSegments + 1) * (heightSegments + 1);

    // initialize
    _init(vertexCount: numVert, withNormals: true, withUV: true);
    name = "Sphere";

    // vertices
    final vertices = _vertices!;
    final normals = _normals!;
    final uvs = _uvs!;
    Vector3 vn = Vector3.zero();

    double x, y, z;
    int i, j, index = 0;
    // vertices: position, normal, texUV
    for (i = 0; i <= heightSegments; i++) {
      final ratioB = i / heightSegments;
      final angleB = pi * ratioB;
      final radiusB = radius * sin(angleB);
      if (0 == i) {
        z = radius;
      } else if (heightSegments == i) {
        z = -radius;
      } else {
        z = radius * cos(angleB);
      }

      for (j = 0; j <= widthSegments; j++) {
        final ratioA = j / widthSegments;
        if (0 == j || widthSegments == j) {
          x = radiusB;
          y = 0;
        } else {
          final angleA = pi * 2 * ratioA;
          x = radiusB * cos(angleA);
          y = radiusB * sin(angleA);
        }
        vn = Vector3(x, y, z).normalized();

        vertices[index] = Vector3(x, y, z);
        normals[index] = vn;
        uvs[index] = Vector2(ratioA, 1.0 - ratioB);

        index++;
      }
    }
    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = radius;

    // solid: triangle-strip
    int numIndex = (widthSegments + 1) * 2 * heightSegments;
    Uint16List indices = Uint16List(numIndex);
    index = 0;

    int startVert;
    for (i = 0; i < heightSegments; i++) {
      startVert = (widthSegments + 1) * i;
      for (j = 0; j <= widthSegments; j++) {
        indices[index] = startVert + j;
        indices[index + 1] = indices[index] + (widthSegments + 1);
        index += 2;
      }
    }
    _faceIndices.add(_M3Indices(WebGL.TRIANGLE_STRIP, indices));

    // wireframe edges
    numIndex = ((widthSegments + 1) * (heightSegments - 1) + 2) + ((widthSegments - 1) * (heightSegments + 1));
    final lines = Uint16List(numIndex);
    index = 0;
    lines[0] = 0;
    for (i = 1; i < heightSegments; i++) // skip top and bottom, because only single dot there
    {
      for (j = 0; j <= widthSegments; j++) {
        index++;
        lines[index] = (widthSegments + 1) * i + j;
      }
    }
    startVert = lines[index] + 1;
    index++;
    lines[index] = startVert;
    for (j = 1; j < widthSegments; j++) // skip first and last of vertical slice
    {
      for (i = 0; i <= heightSegments; i++) {
        if (j % 2 != 0) {
          startVert = (widthSegments + 1) * (heightSegments - i) + j; // reverse order
        } else {
          startVert = (widthSegments + 1) * i + j; // common order
        }

        index++;
        lines[index] = startVert;
      }
    }
    _edgeIndices.add(_M3Indices(WebGL.LINE_STRIP, lines));
  }
}
