part of '../geom.dart';

/// A rectangular box (cuboid) geometry with configurable dimensions.
///
/// Creates a box centered at the origin with the specified width, height, and depth.
class M3BoxGeom extends M3Geom {
  M3BoxGeom(double width, double height, double depth) {
    // initialize
    _init(vertexCount: 24, withNormals: true, withUV: true);
    name = "Box";
    double hx = width / 2;
    double hy = height / 2;
    double hz = depth / 2;

    // vertices
    final vertices = _vertices!;
    vertices[0] = Vector3(-hx, -hy, -hz);
    vertices[1] = Vector3(hx, -hy, -hz);
    vertices[2] = Vector3(-hx, hy, -hz);
    vertices[3] = Vector3(hx, hy, -hz);
    vertices[4] = Vector3(-hx, -hy, hz);
    vertices[5] = Vector3(hx, -hy, hz);
    vertices[6] = Vector3(-hx, hy, hz);
    vertices[7] = Vector3(hx, hy, hz);

    vertices[8] = vertices[0];
    vertices[9] = vertices[1];
    vertices[10] = vertices[2];
    vertices[11] = vertices[3];
    vertices[12] = vertices[4];
    vertices[13] = vertices[5];
    vertices[14] = vertices[6];
    vertices[15] = vertices[7];

    vertices[16] = vertices[0];
    vertices[17] = vertices[1];
    vertices[18] = vertices[2];
    vertices[19] = vertices[3];
    vertices[20] = vertices[4];
    vertices[21] = vertices[5];
    vertices[22] = vertices[6];
    vertices[23] = vertices[7];

    final uvs = _uvs!;
    uvs[0] = Vector2.zero();
    uvs[1] = Vector2(1, 0);
    uvs[2] = Vector2(0, 1);
    uvs[3] = Vector2(1, 1);
    uvs[4] = Vector2.zero();
    uvs[5] = Vector2(1, 0);
    uvs[6] = Vector2(0, 1);
    uvs[7] = Vector2(1, 1);

    uvs[8] = Vector2.zero();
    uvs[9] = Vector2(1, 0);
    uvs[10] = Vector2.zero();
    uvs[11] = Vector2(1, 0);
    uvs[12] = Vector2(0, 1);
    uvs[13] = Vector2(1, 1);
    uvs[14] = Vector2(0, 1);
    uvs[15] = Vector2(1, 1);

    uvs[16] = Vector2.zero();
    uvs[17] = Vector2.zero();
    uvs[18] = Vector2(1, 0);
    uvs[19] = Vector2(1, 0);
    uvs[20] = Vector2(0, 1);
    uvs[21] = Vector2(0, 1);
    uvs[22] = Vector2(1, 1);
    uvs[23] = Vector2(1, 1);

    // normals
    if (_normals != null) {
      final normals = _normals!;
      Vector3 postiveX = Vector3(1, 0, 0);
      Vector3 negativeX = Vector3(-1, 0, 0);
      Vector3 postiveY = Vector3(0, 1, 0);
      Vector3 negativeY = Vector3(0, -1, 0);
      Vector3 postiveZ = Vector3(0, 0, 1);
      Vector3 negativeZ = Vector3(0, 0, -1);

      normals[0] = negativeZ;
      normals[1] = negativeZ;
      normals[2] = negativeZ;
      normals[3] = negativeZ;

      normals[4] = postiveZ;
      normals[5] = postiveZ;
      normals[6] = postiveZ;
      normals[7] = postiveZ;

      normals[8] = negativeY;
      normals[9] = negativeY;
      normals[10] = postiveY;
      normals[11] = postiveY;

      normals[12] = negativeY;
      normals[13] = negativeY;
      normals[14] = postiveY;
      normals[15] = postiveY;

      normals[16] = negativeX;
      normals[17] = postiveX;
      normals[18] = negativeX;
      normals[19] = postiveX;

      normals[20] = negativeX;
      normals[21] = postiveX;
      normals[22] = negativeX;
      normals[23] = postiveX;
    }
    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = Vector3(hx, hy, hz).length;

    // solid faces
    _faceIndices.add(
      _M3Indices(
        WebGL.TRIANGLES,
        Uint16List.fromList([
          0, 2, 1, 1, 2, 3, // buttom face
          4, 5, 6, 6, 5, 7, // top face
          8, 9, 12, 12, 9, 13, // back face
          10, 14, 11, 11, 14, 15, // front face
          16, 20, 18, 18, 20, 22, // left face
          17, 19, 21, 21, 19, 23, // right face
        ]),
      ),
    );

    // wireframe edges
    _edgeIndices.add(
      _M3Indices(
        WebGL.LINES,
        Uint16List.fromList([
          0, 1, 1, 3, 3, 2, 2, 0, // bottom part
          4, 5, 5, 7, 7, 6, 6, 4, // top part
          0, 4, 1, 5, 2, 6, 3, 7, // vertical part
        ]),
      ),
    );
  }
}
