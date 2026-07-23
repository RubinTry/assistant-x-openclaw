import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math.dart';
import '../geom/geom.dart';

/// Loader for Wavefront (.obj) 3D model files.
///
/// This loader parses vertex positions, normals, and UVs, and handles
/// basic triangulation for polygon faces.
class M3ObjLoader {
  /// Loads an OBJ file from the assets folder.
  ///
  /// Note: This method is primarily used for local assets. For unified loading,
  /// use [M3Mesh.load] instead.
  static Future<M3Geom> load(String path) async {
    final data = await rootBundle.loadString('assets/$path');
    return parse(data, path);
  }

  /// Parses raw OBJ string data into an [M3Geom] object.
  ///
  /// This parser handles:
  /// - `v`: Vertex positions
  /// - `vn`: Vertex normals
  /// - `vt`: Texture coordinates (UVs)
  /// - `f`: Faces (automatically triangulated if necessary)
  static M3Geom parse(String data, String name) {
    // Temporary storage for raw data from the file
    List<Vector3> vertices = [];
    List<Vector3> normals = [];
    List<Vector2> uvs = [];

    // Final buffers after deduplication and indexing
    List<int> indices = [];
    List<double> finalVertices = [];
    List<double> finalNormals = [];
    List<double> finalUvs = [];

    // Deduplication map to store unique vertex/uv/normal combinations
    Map<String, int> uniqueVertices = {};

    final lines = data.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split(RegExp(r'\s+'));
      final type = parts[0];

      if (type == 'v') {
        // Vertex position: v x y z
        vertices.add(Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3])));
      } else if (type == 'vn') {
        // Vertex normal: vn x y z
        normals.add(Vector3(double.parse(parts[1]), double.parse(parts[2]), double.parse(parts[3])));
      } else if (type == 'vt') {
        // Texture coordinate: vt u v
        uvs.add(Vector2(double.parse(parts[1]), double.parse(parts[2])));
      } else if (type == 'f') {
        // Face definition: f v1/vt1/vn1 v2/vt2/vn2 ...
        // Triangulate faces using a triangle fan approach
        for (int i = 1; i < parts.length - 1; i++) {
          _processVertex(
            parts[1],
            vertices,
            normals,
            uvs,
            uniqueVertices,
            indices,
            finalVertices,
            finalNormals,
            finalUvs,
          );
          _processVertex(
            parts[i],
            vertices,
            normals,
            uvs,
            uniqueVertices,
            indices,
            finalVertices,
            finalNormals,
            finalUvs,
          );
          _processVertex(
            parts[i + 1],
            vertices,
            normals,
            uvs,
            uniqueVertices,
            indices,
            finalVertices,
            finalNormals,
            finalUvs,
          );
        }
      }
    }

    final geom = M3ObjGeom(finalVertices, finalNormals, finalUvs, indices);
    geom.name = name;
    return geom;
  }

  /// Processes a single vertex definition string from a face and manages indexing.
  ///
  /// Handles deduplication by checking if the exact combination of attributes
  /// has already been processed.
  static void _processVertex(
    String vertexData,
    List<Vector3> vertices,
    List<Vector3> normals,
    List<Vector2> uvs,
    Map<String, int> uniqueVertices,
    List<int> indices,
    List<double> finalVertices,
    List<double> finalNormals,
    List<double> finalUvs,
  ) {
    // If we've seen this exact vertex string before, just add the existing index
    if (uniqueVertices.containsKey(vertexData)) {
      indices.add(uniqueVertices[vertexData]!);
      return;
    }

    // Parse the v/vt/vn indices
    final parts = vertexData.split('/');
    final vIndex = int.parse(parts[0]) - 1; // OBJ indices are 1-based
    final vtIndex = parts.length > 1 && parts[1].isNotEmpty ? int.parse(parts[1]) - 1 : -1;
    final vnIndex = parts.length > 2 && parts[2].isNotEmpty ? int.parse(parts[2]) - 1 : -1;

    // Position (Required)
    final v = vertices[vIndex];
    finalVertices.addAll([v.x, v.y, v.z]);

    // Normal (Optional, defaults to +Z)
    if (vnIndex >= 0) {
      final vn = normals[vnIndex];
      finalNormals.addAll([vn.x, vn.y, vn.z]);
    } else {
      finalNormals.addAll([0, 0, 1]);
    }

    // UV (Optional, defaults to [0, 0])
    if (vtIndex >= 0) {
      final vt = uvs[vtIndex];
      finalUvs.addAll([vt.x, vt.y]);
    } else {
      finalUvs.addAll([0, 0]);
    }

    // Create a new index for this unique combination
    int newIndex = uniqueVertices.length;
    uniqueVertices[vertexData] = newIndex;
    indices.add(newIndex);
  }
}
