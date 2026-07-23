import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_lists.dart';
import 'package:image/image.dart' as img;

// Macbear3D engine
import '../m3_internal.dart';
import '../gltf/gltf_parser.dart';

import 'primitive/height_field.dart';
import 'text/ear_clipping.dart';

// part for geom
part 'debug/debug_axis_geom.dart';
part 'debug/debug_sphere_geom.dart';
part 'primitive/box_geom.dart';
part 'primitive/capsule_geom.dart';
part 'primitive/cylinder_geom.dart';
part 'primitive/ellipsoid_geom.dart';
part 'primitive/octahedral_geom.dart';
part 'primitive/plane_geom.dart';
part 'primitive/pyramid_geom.dart';
part 'primitive/sphere_geom.dart';
part 'primitive/terrain_geom.dart';
part 'primitive/torus_geom.dart';
part 'text/text_geom.dart';
part 'text/contour.dart';
part 'gltf_geom.dart';
part 'obj_geom.dart';

enum M3ShadingMode { flat, smooth }

/// Internal class to manage index buffers for geometry rendering.
///
/// Handles both face indices (for solid rendering) and edge indices
/// (for wireframe rendering).
class _M3Indices {
  RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;

  // always GL_TRIANGLES, GL_TRIANGLE_STRIP, GL_LINES, GL_LINE_STRIP
  // not supported: GL_TRIANGLE_FAN, GL_LINE_LOOP
  final int _primitiveType;
  int _count = 0; // element count
  int _indexType = WebGL.UNSIGNED_SHORT; // or WebGL.UNSIGNED_INT for 32 bits index
  late Buffer _indexBuffer;

  _M3Indices(this._primitiveType, TypedData indices) {
    dynamic idxList;
    if (indices is Uint16List) {
      idxList = toU16List(indices);
      _indexType = WebGL.UNSIGNED_SHORT;
      _count = indices.length;
    } else if (indices is Uint32List) {
      idxList = toU32List(indices);
      _indexType = WebGL.UNSIGNED_INT;
      _count = indices.length;
    } else {
      throw ArgumentError('indices must be Uint16List or Uint32List');
    }

    // buffers for indices
    _indexBuffer = gl.createBuffer();
    gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _indexBuffer);
    gl.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, idxList, WebGL.STATIC_DRAW);
  }

  int get primitiveCount {
    switch (_primitiveType) {
      case WebGL.TRIANGLES:
        return _count ~/ 3;
      case WebGL.TRIANGLE_STRIP:
        return _count > 2 ? _count - 2 : 0;
      case WebGL.LINES:
        return _count ~/ 2;
      case WebGL.LINE_STRIP:
        return _count > 1 ? _count - 1 : 0;
      case WebGL.POINTS:
        return _count;
      default:
        return 0;
    }
  }

  /// Draws the indexed geometry using the current rendering context.
  void draw() {
    gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _indexBuffer);
    gl.drawElements(_primitiveType, _count, _indexType, 0);
  }

  /// Releases GPU resources associated with this index buffer.
  void dispose() {
    gl.deleteBuffer(_indexBuffer);
  }
}

/// Bounding box and sphere for geometry.
class M3Bounding {
  Aabb3 aabb = Aabb3();
  Sphere sphere = Sphere();
}

/// Abstract base class for all 3D geometry primitives.
///
/// Provides vertex buffer management, rendering methods, and support for
/// positions, normals, UV coordinates, colors, and skeletal animation data.
abstract class M3Geom {
  RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;
  static const int radialSegments = 16;

  String name = "Noname";
  M3Bounding localBounding = M3Bounding();

  int _vertexCount = 0;
  Vector3List? _vertices; // vertex positions
  Vector3List? _normals; // vertex normals
  Vector2List? _uvs; // vertex texture coordinates(u,v)
  Vector3List? _colors; // vertex colors
  Uint16List? _joints; // vertex bone indices (4 per vertex)
  Float32List? _weights; // vertex bone weights (4 per vertex)

  // VBO: vertex buffer object
  Buffer? _vertexBuffer;
  Buffer? _normalBuffer;
  Buffer? _uvBuffer;
  Buffer? _colorBuffer;
  Buffer? _jointBuffer;
  Buffer? _weightBuffer;

  // list of indices for faces and edges
  final List<_M3Indices> _faceIndices = []; // solid faces
  final List<_M3Indices> _edgeIndices = []; // wireframe edges

  int get vertexCount => _vertexCount;
  int getTriangleCount({M3FillMode fillMode = .solid}) {
    int count = 0;
    final indices = fillMode == .solid ? _faceIndices : _edgeIndices;
    for (var surface in indices) {
      count += surface.primitiveCount;
    }
    return count;
  }

  @override
  String toString() {
    return 'M3Geom{vertexCount: $_vertexCount, name: $name}';
  }

  void _init({required int vertexCount, bool withNormals = false, bool withUV = false, bool withColors = false}) {
    assert(vertexCount >= 0, 'indexCount must be non-negative');
    _vertexCount = vertexCount;
    _vertices = Vector3List(vertexCount);
    if (withNormals) {
      _normals = Vector3List(vertexCount);
    }
    if (withUV) {
      _uvs = Vector2List(vertexCount);
    }
    if (withColors) {
      _colors = Vector3List(vertexCount);
    }
    if (vertexCount > 0) {
      // Joint and weights are usually 4 per vertex
      _joints = Uint16List(vertexCount * 4);
      _weights = Float32List(vertexCount * 4);
    }
  }

  // buffers for vertices, normals after init
  void _createVBO() {
    if (_vertices == null) {
      return;
    }
    // calculate AABB, boundingSphere
    if (_vertexCount > 0) {
      final v = Vector3.zero();
      _vertices!.load(0, v);
      localBounding.aabb.min.setFrom(v);
      localBounding.aabb.max.setFrom(v);
      for (int i = 1; i < _vertexCount; i++) {
        _vertices!.load(i, v);
        localBounding.aabb.hullPoint(v);
      }

      // Update bounding sphere
      localBounding.aabb.copyCenter(localBounding.sphere.center);
      localBounding.sphere.radius = localBounding.aabb.min.distanceTo(localBounding.aabb.max) * 0.5;
    }

    _vertexBuffer = gl.createBuffer();
    gl.bindBuffer(WebGL.ARRAY_BUFFER, _vertexBuffer);
    gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_vertices!.buffer), WebGL.STATIC_DRAW);
    _vertices = null;

    if (_normals != null) {
      _normalBuffer = gl.createBuffer();
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _normalBuffer);
      gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_normals!.buffer), WebGL.STATIC_DRAW);
      _normals = null;
    }

    if (_uvs != null) {
      _uvBuffer = gl.createBuffer();
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _uvBuffer);
      gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_uvs!.buffer), WebGL.STATIC_DRAW);
      _uvs = null;
    }

    if (_colors != null) {
      _colorBuffer = gl.createBuffer();
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _colorBuffer);
      gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_colors!.buffer), WebGL.STATIC_DRAW);
      _colors = null;
    }

    if (_joints != null) {
      _jointBuffer = gl.createBuffer();
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _jointBuffer);
      gl.bufferData(WebGL.ARRAY_BUFFER, toU16List(_joints!), WebGL.STATIC_DRAW);
      _joints = null;
    }

    if (_weights != null) {
      _weightBuffer = gl.createBuffer();
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _weightBuffer);
      gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_weights!), WebGL.STATIC_DRAW);
      _weights = null;
    }
  }

  /// Computes vertex normals automatically based on triangle geometry.
  ///
  /// This method should be called after filling [_vertices] and providing [indices],
  /// but before calling [_createVBO()].
  void computeNormals(List<int> indices) {
    if (_vertices == null || _vertexCount == 0 || indices.isEmpty) return;

    // 1. Initialize normals if not already present
    _normals ??= Vector3List(_vertexCount);
    for (int i = 0; i < _vertexCount; i++) {
      _normals!.setValues(i, 0.0, 0.0, 0.0);
    }

    final vA = Vector3.zero();
    final vB = Vector3.zero();
    final vC = Vector3.zero();
    final edge1 = Vector3.zero();
    final edge2 = Vector3.zero();
    final triNormal = Vector3.zero();

    // 2. Accumulate face normals for each vertex
    for (int i = 0; i < indices.length - 2; i += 3) {
      final i1 = indices[i];
      final i2 = indices[i + 1];
      final i3 = indices[i + 2];

      _vertices!.load(i1, vA);
      _vertices!.load(i2, vB);
      _vertices!.load(i3, vC);

      edge1.setFrom(vB);
      edge1.sub(vA);
      edge2.setFrom(vC);
      edge2.sub(vA);

      edge1.crossInto(edge2, triNormal);
      if (triNormal.length2 < 1e-10) continue; // Skip degenerate triangles
      triNormal.normalize();

      // Accumulate into vertex normals
      for (final idx in [i1, i2, i3]) {
        _normals!.load(idx, vA);
        vA.add(triNormal);
        _normals!.setValues(idx, vA.x, vA.y, vA.z);
      }
    }

    // 3. Normalize all vertex normals for smooth shading
    for (int i = 0; i < _vertexCount; i++) {
      _normals!.load(i, vA);
      if (vA.length2 > 0) {
        vA.normalize();
        _normals!.setValues(i, vA.x, vA.y, vA.z);
      }
    }
  }

  /// Generates wireframe edge indices from triangle indices.
  ///
  /// Optimized to add each edge only once.
  void _generateEdgeIndices(List<int> indices) {
    if (indices.isEmpty) return;

    final Set<int> edges = {};
    final List<int> lineIndices = [];

    void addEdge(int i1, int i2) {
      final int a = i1 < i2 ? i1 : i2;
      final int b = i1 < i2 ? i2 : i1;
      final int key = (a << 16) | b;
      if (edges.add(key)) {
        lineIndices.add(a);
        lineIndices.add(b);
      }
    }

    for (int i = 0; i < indices.length - 2; i += 3) {
      addEdge(indices[i], indices[i + 1]);
      addEdge(indices[i + 1], indices[i + 2]);
      addEdge(indices[i + 2], indices[i]);
    }

    if (lineIndices.isNotEmpty) {
      final indices = (_vertexCount > 65535) ? Uint32List.fromList(lineIndices) : Uint16List.fromList(lineIndices);
      _edgeIndices.add(_M3Indices(WebGL.LINES, indices));
    }
  }

  /// Releases all GPU resources associated with this geometry.
  void dispose() {
    if (_vertexBuffer != null) {
      gl.deleteBuffer(_vertexBuffer!);
      _vertexBuffer = null;
    }
    if (_normalBuffer != null) {
      gl.deleteBuffer(_normalBuffer!);
      _normalBuffer = null;
    }
    if (_uvBuffer != null) {
      gl.deleteBuffer(_uvBuffer!);
      _uvBuffer = null;
    }
    if (_colorBuffer != null) {
      gl.deleteBuffer(_colorBuffer!);
      _colorBuffer = null;
    }
    if (_jointBuffer != null) {
      gl.deleteBuffer(_jointBuffer!);
      _jointBuffer = null;
    }
    if (_weightBuffer != null) {
      gl.deleteBuffer(_weightBuffer!);
      _weightBuffer = null;
    }
    _vertices = null;
    _normals = null;
    _uvs = null;
    _colors = null;

    // dispose indices
    for (var surface in _faceIndices) {
      surface.dispose();
    }
    for (var wireframe in _edgeIndices) {
      wireframe.dispose();
    }
    _faceIndices.clear();
    _edgeIndices.clear();
  }

  /// Renders the geometry using the specified shader program.
  void draw(M3Program prog, {M3FillMode fillMode = .solid}) {
    if (_vertexBuffer != null) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _vertexBuffer);
      gl.enableVertexAttribArray(prog.attribVertex.id);
      gl.vertexAttribPointer(prog.attribVertex.id, 3, WebGL.FLOAT, false, 0, 0);
    }
    if (_normalBuffer != null && prog.attribNormal.id >= 0) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _normalBuffer);
      gl.enableVertexAttribArray(prog.attribNormal.id);
      gl.vertexAttribPointer(prog.attribNormal.id, 3, WebGL.FLOAT, false, 0, 0);
    }
    if (_uvBuffer != null && prog.attribUV.id >= 0) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _uvBuffer);
      gl.enableVertexAttribArray(prog.attribUV.id);
      gl.vertexAttribPointer(prog.attribUV.id, 2, WebGL.FLOAT, false, 0, 0);
    }
    if (_colorBuffer != null && prog.attribColor.id >= 0) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _colorBuffer);
      gl.enableVertexAttribArray(prog.attribColor.id);
      gl.vertexAttribPointer(prog.attribColor.id, 3, WebGL.FLOAT, false, 0, 0);
    }
    if (_jointBuffer != null && prog.attribBoneIndex.id >= 0) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _jointBuffer);
      gl.enableVertexAttribArray(prog.attribBoneIndex.id);
      gl.vertexAttribPointer(prog.attribBoneIndex.id, 4, WebGL.UNSIGNED_SHORT, false, 0, 0);
    }
    if (_weightBuffer != null && prog.attribBoneWeight.id >= 0) {
      gl.bindBuffer(WebGL.ARRAY_BUFFER, _weightBuffer);
      gl.enableVertexAttribArray(prog.attribBoneWeight.id);
      gl.vertexAttribPointer(prog.attribBoneWeight.id, 4, WebGL.FLOAT, false, 0, 0);
    }

    List<_M3Indices> drawSurfaces = fillMode == .solid ? _faceIndices : _edgeIndices;
    for (var surface in drawSurfaces) {
      surface.draw();
    }

    if (_vertexBuffer != null) {
      gl.disableVertexAttribArray(prog.attribVertex.id);
    }
    if (_normalBuffer != null && prog.attribNormal.id >= 0) {
      gl.disableVertexAttribArray(prog.attribNormal.id);
    }
    if (_uvBuffer != null && prog.attribUV.id >= 0) {
      gl.disableVertexAttribArray(prog.attribUV.id);
    }
    if (_colorBuffer != null && prog.attribColor.id >= 0) {
      gl.disableVertexAttribArray(prog.attribColor.id);
    }
    if (_jointBuffer != null && prog.attribBoneIndex.id >= 0) {
      gl.disableVertexAttribArray(prog.attribBoneIndex.id);
    }
    if (_weightBuffer != null && prog.attribBoneWeight.id >= 0) {
      gl.disableVertexAttribArray(prog.attribBoneWeight.id);
    }
  }
}
