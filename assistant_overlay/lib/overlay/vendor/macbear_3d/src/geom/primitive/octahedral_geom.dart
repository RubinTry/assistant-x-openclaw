part of '../geom.dart';

/// An octahedral geometry with a configurable radius.
///
/// Creates a regular octahedron centered at the origin.
class M3OctahedralGeom extends M3Geom {
  M3OctahedralGeom(double radius, {Vector3? bias}) {
    // initialize
    _init(vertexCount: 24, withNormals: true, withUV: true);
    name = "Octahedral";

    final vertices = _vertices!;
    final uvs = _uvs!;

    // bias by X-axis
    Vector3 offset = Vector3.zero();
    if (bias != null) {
      offset = bias * radius; // bias [-1, +1]
    }
    // 6 unique vertices of the octahedron
    final top = Vector3(offset.x, radius, offset.z);
    final bottom = Vector3(offset.x, -radius, offset.z);
    final right = Vector3(radius, offset.y, offset.z);
    final left = Vector3(-radius, offset.y, offset.z);
    final front = Vector3(offset.x, offset.y, radius);
    final back = Vector3(offset.x, offset.y, -radius);

    // 8 faces, 3 vertices each
    final List<Vector3> faceVerts = [
      // Top half
      front, right, top,
      right, back, top,
      back, left, top,
      left, front, top,
      // Bottom half
      right, front, bottom,
      back, right, bottom,
      left, back, bottom,
      front, left, bottom,
    ];

    List<int> indices = List<int>.generate(24, (i) => i);

    for (int i = 0; i < 24; i++) {
      vertices[i] = faceVerts[i].clone();
    }

    // texture coordinates
    for (int i = 0; i < 24; i += 3) {
      uvs[i] = Vector2(0.0, 0.0);
      uvs[i + 1] = Vector2(1.0, 0.0);
      uvs[i + 2] = Vector2(0.5, 1.0);
    }

    // Flat shading normals computed directly from face triangles
    computeNormals(indices);

    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = radius;

    // solid faces
    _faceIndices.add(_M3Indices(WebGL.TRIANGLES, Uint16List.fromList(indices)));

    // wireframe edges
    _generateEdgeIndices(indices);
  }
}
