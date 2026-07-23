part of 'geom.dart';

/// Geometry loaded from a Wavefront OBJ file.
///
/// Accepts pre-parsed vertex, normal, UV, and index data.
class M3ObjGeom extends M3Geom {
  M3ObjGeom(List<double> vertices, List<double> normals, List<double> uvs, List<int> indices) {
    _init(vertexCount: vertices.length ~/ 3, withNormals: true, withUV: true);

    // Copy data to buffers
    for (int i = 0; i < vertices.length; i++) {
      _vertices!.buffer[i] = vertices[i];
    }
    for (int i = 0; i < normals.length; i++) {
      _normals!.buffer[i] = normals[i];
    }
    for (int i = 0; i < uvs.length; i++) {
      _uvs!.buffer[i] = uvs[i];
    }

    // vertex buffer object
    _createVBO();

    // Create indices
    final indicesArray = (_vertexCount > 65535) ? Uint32List.fromList(indices) : Uint16List.fromList(indices);
    _faceIndices.add(_M3Indices(WebGL.TRIANGLES, indicesArray));

    // Create wireframe indices
    _generateEdgeIndices(indices);
  }
}
