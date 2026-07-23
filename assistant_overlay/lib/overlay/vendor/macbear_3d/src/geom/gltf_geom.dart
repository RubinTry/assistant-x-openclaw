part of 'geom.dart';

/// Geometry loaded from a glTF model primitive.
///
/// Constructs GPU-ready VBO/IBO from [GltfPrimitive] data.
class M3GltfGeom extends M3Geom {
  M3GltfGeom.fromPrimitive(GltfPrimitive primitive) {
    final positions = primitive.getPositions();
    if (positions == null || positions.isEmpty) {
      throw Exception('glTF primitive has no POSITION attribute');
    }

    final normals = primitive.getNormals();
    final uvs = primitive.getTexCoords();
    final indices = primitive.getIndices();
    final vertexCount = primitive.vertexCount;

    _init(vertexCount: vertexCount, withNormals: normals != null || primitive.mode == 4, withUV: uvs != null);

    // Prepare indices for normal calculation and VBO creation
    final List<int> finalIndices = indices ?? List<int>.generate(vertexCount, (i) => i);

    // Copy Positions
    for (int i = 0; i < positions.length; i++) {
      _vertices!.buffer[i] = positions[i];
    }

    // Copy or Compute Normals
    if (normals != null && _normals != null) {
      for (int i = 0; i < normals.length; i++) {
        _normals!.buffer[i] = normals[i];
      }
    } else if (primitive.mode == 4) {
      // Mode 4 = TRIANGLES, compute smooth normals if missing
      computeNormals(finalIndices);
    }

    // Copy UVs
    if (uvs != null && _uvs != null) {
      for (int i = 0; i < uvs.length; i++) {
        _uvs!.buffer[i] = uvs[i];
      }
    }

    // Copy Joints
    final joints = primitive.getJoints();
    if (joints != null && _joints != null) {
      for (int i = 0; i < joints.length; i++) {
        _joints![i] = joints[i];
      }
    }

    // Copy Weights
    final weights = primitive.getWeights();
    if (weights != null && _weights != null) {
      for (int i = 0; i < weights.length; i++) {
        _weights![i] = weights[i];
      }
    }

    // vertex buffer object
    _createVBO();

    // Create face indices
    final indicesArray = (_vertexCount > 65535) ? Uint32List.fromList(finalIndices) : Uint16List.fromList(finalIndices);
    _faceIndices.add(_M3Indices(_glMode(primitive.mode), indicesArray));

    // Create wireframe indices
    if (primitive.mode == 4) {
      _generateEdgeIndices(finalIndices);
    }

    // Apply material logic moved to M3Mesh construction
  }

  /// 從 glTF mode 轉換為 WebGL primitive type
  static int _glMode(int gltfMode) {
    switch (gltfMode) {
      case 0:
        return WebGL.POINTS;
      case 1:
        return WebGL.LINES;
      case 2:
        return WebGL.LINE_LOOP;
      case 3:
        return WebGL.LINE_STRIP;
      case 4:
        return WebGL.TRIANGLES;
      case 5:
        return WebGL.TRIANGLE_STRIP;
      case 6:
        return WebGL.TRIANGLE_FAN;
      default:
        return WebGL.TRIANGLES;
    }
  }
}
