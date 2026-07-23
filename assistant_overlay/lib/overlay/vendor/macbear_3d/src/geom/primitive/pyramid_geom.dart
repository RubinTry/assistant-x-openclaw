part of '../geom.dart';

/// A four-sided pyramid geometry with a rectangular base and apex.
///
/// The base is centered at Z=-depth/2 and the apex is at Z=+depth/2.
class M3PyramidGeom extends M3Geom {
  M3PyramidGeom(double width, double height, double depth, {M3Axis axis = M3Axis.z}) {
    // initialize
    _init(vertexCount: 16, withNormals: true, withUV: true);
    name = "Pyramid";
    double hx = width / 2;
    double hy = height / 2;
    double hz = depth / 2;

    final rot = Matrix3.identity();
    if (axis == M3Axis.x) {
      rot.setRotationY(pi / 2);
    } else if (axis == M3Axis.y) {
      rot.setRotationX(-pi / 2);
    }

    Vector3 transform(double x, double y, double z) {
      final v = Vector3(x, y, z);
      if (axis != M3Axis.z) {
        rot.transform(v);
      }
      return v;
    }

    // vertices
    final vertices = _vertices!;
    vertices[0] = transform(-hx, -hy, -hz);
    vertices[1] = transform(hx, -hy, -hz);
    vertices[2] = transform(-hx, hy, -hz);
    vertices[3] = transform(hx, hy, -hz);

    vertices[4] = transform(0, 0, hz);
    vertices[5] = transform(-hx, -hy, -hz);
    vertices[6] = transform(hx, -hy, -hz);

    vertices[7] = transform(0, 0, hz);
    vertices[8] = transform(hx, -hy, -hz);
    vertices[9] = transform(hx, hy, -hz);

    vertices[10] = transform(0, 0, hz);
    vertices[11] = transform(hx, hy, -hz);
    vertices[12] = transform(-hx, hy, -hz);

    vertices[13] = transform(0, 0, hz);
    vertices[14] = transform(-hx, hy, -hz);
    vertices[15] = transform(-hx, -hy, -hz);

    // normals
    if (_normals != null) {
      final normals = _normals!;
      final vNegZ = transform(0, 0, -1);

      normals[0] = vNegZ;
      normals[1] = vNegZ.clone();
      normals[2] = vNegZ.clone();
      normals[3] = vNegZ.clone();

      final dir0 = vertices[0] - vertices[4];
      final dir1 = vertices[1] - vertices[4];
      final dir2 = vertices[2] - vertices[4];
      final dir3 = vertices[3] - vertices[4];

      final nBack = dir0.cross(dir1).normalized();
      normals[4] = nBack;
      normals[5] = nBack.clone();
      normals[6] = nBack.clone();

      final nRight = dir1.cross(dir3).normalized();
      normals[7] = nRight;
      normals[8] = nRight.clone();
      normals[9] = nRight.clone();

      final nFront = dir3.cross(dir2).normalized();
      normals[10] = nFront;
      normals[11] = nFront.clone();
      normals[12] = nFront.clone();

      final nLeft = dir2.cross(dir0).normalized();
      normals[13] = nLeft;
      normals[14] = nLeft.clone();
      normals[15] = nLeft.clone();
    }

    // texture coordinate(u,v)
    if (_uvs != null) {
      final uvs = _uvs!;

      uvs[0] = Vector2(0.5, 0);
      uvs[1] = Vector2(0, 0.5);
      uvs[2] = Vector2(1, 0.5);
      uvs[3] = Vector2(0.5, 1);

      uvs[4] = Vector2(0, 0);
      uvs[5] = uvs[0];
      uvs[6] = uvs[1];

      uvs[7] = Vector2(0, 1);
      uvs[8] = uvs[1];
      uvs[9] = uvs[3];

      uvs[10] = Vector2(1, 1);
      uvs[11] = uvs[3];
      uvs[12] = uvs[2];

      uvs[13] = Vector2(1, 0);
      uvs[14] = uvs[2];
      uvs[15] = uvs[0];
    }

    // vertex buffer object
    _createVBO();
    localBounding.sphere.radius = Vector3(hx, hy, hz).length;

    // solid faces
    _faceIndices.add(
      _M3Indices(
        WebGL.TRIANGLES,
        Uint16List.fromList([
          0, 2, 1, 1, 2, 3, // bottom face
          4, 5, 6, // back face
          7, 8, 9, // right face
          10, 11, 12, // front face
          13, 14, 15, // left face
        ]),
      ),
    );

    // wireframe edges
    _edgeIndices.add(
      _M3Indices(
        WebGL.LINES,
        Uint16List.fromList([
          0, 1, 1, 3, 3, 2, 2, 0, // bottom part
          4, 0, 4, 1, 4, 2, 4, 3, // side parts
        ]),
      ),
    );
  }

}
