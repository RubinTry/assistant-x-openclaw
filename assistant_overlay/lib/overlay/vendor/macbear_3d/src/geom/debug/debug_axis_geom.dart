part of '../geom.dart';

/// A coordinate axis helper geometry for debugging and visualization.
///
/// Displays X, Y, and Z axes as lines from the origin.
class M3DebugAxisGeom extends M3Geom {
  M3DebugAxisGeom({double size = 1.0}) {
    // initialize
    _init(vertexCount: 4);
    name = "Axis";

    // vertices
    final vertices = _vertices!;
    vertices[0] = Vector3(0, 0, 0);
    vertices[1] = Vector3(size, 0, 0);
    vertices[2] = Vector3(0, size, 0);
    vertices[3] = Vector3(0, 0, size);

    // vertex buffer object
    _createVBO();

    // solid faces
    _faceIndices.add(
      _M3Indices(
        WebGL.TRIANGLES,
        Uint16List.fromList([
          0, 1, 2, // XY face
        ]),
      ),
    );

    _faceIndices.add(
      _M3Indices(
        WebGL.LINES,
        Uint16List.fromList([
          0, 1, 0, 2, 0, 3, // XYZ axis lines
          1, 2, // XY edge
        ]),
      ),
    );

    // none wireframe edges
  }
}
