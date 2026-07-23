part of '../geom.dart';

/// A subdivided plane geometry with configurable segments and optional height mapping.
///
/// Supports UV scaling, face flipping, and custom vertex callbacks for terrain generation.
class M3PlaneGeom extends M3Geom {
  // sample callback to Z value
  static double formulaZ(double x, double y) {
    return 0.0;
  }

  // plane width, height
  Function(double, double)? funcVertex;
  double width;
  double height;
  int widthSegments; // columns X
  int heightSegments; // rows Y
  M3Axis axis; // plane axis
  final M3ShadingMode shading;

  // vertex order: row-major align by X-axis (-sx/2 ~ sx/2), column from (sy/2 ~ -sy/2)
  // default face-flip(false) means face-up; face-flip(true) means face-down
  M3PlaneGeom(
    this.width,
    this.height, {
    this.widthSegments = 6,
    this.heightSegments = 6,
    Vector2? uvScale,
    Function(double x, double y)? onVertex,
    bool flipFace = false,
    this.axis = M3Axis.z,
    this.shading = M3ShadingMode.smooth,
  }) {
    funcVertex = onVertex;
    name = "Plane";
    uvScale = uvScale ?? Vector2(1, 1);
    final hx = width * 0.5, hy = height * 0.5;

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

    if (shading == M3ShadingMode.flat) {
      int numVert = widthSegments * heightSegments * 6;
      _init(vertexCount: numVert, withNormals: true, withUV: true);
      final vertices = _vertices!;
      final uvs = _uvs!;
      final normals = _normals!;

      int vIdx = 0;
      for (int i = 0; i < heightSegments; i++) {
        for (int j = 0; j < widthSegments; j++) {
          double rx0 = j / widthSegments;
          double rx1 = (j + 1) / widthSegments;
          double ry0 = i / heightSegments;
          double ry1 = (i + 1) / heightSegments;

          double x0 = width * rx0 - hx;
          double x1 = width * rx1 - hx;
          double y0 = hy - height * ry0;
          double y1 = hy - height * ry1;

          double z00 = onVertex?.call(x0, y0) ?? 0;
          double z10 = onVertex?.call(x1, y0) ?? 0;
          double z01 = onVertex?.call(x0, y1) ?? 0;
          double z11 = onVertex?.call(x1, y1) ?? 0;

          Vector3 v00 = transform(x0, y0, z00);
          Vector3 v10 = transform(x1, y0, z10);
          Vector3 v01 = transform(x0, y1, z01);
          Vector3 v11 = transform(x1, y1, z11);

          Vector2 uv00 = Vector2(rx0 * uvScale.x, ry0 * uvScale.y);
          Vector2 uv10 = Vector2(rx1 * uvScale.x, ry0 * uvScale.y);
          Vector2 uv01 = Vector2(rx0 * uvScale.x, ry1 * uvScale.y);
          Vector2 uv11 = Vector2(rx1 * uvScale.x, ry1 * uvScale.y);

          // Triangle 1: v00, v01, v10 (CCW)
          vertices[vIdx] = v00;
          vertices[vIdx + 1] = v01;
          vertices[vIdx + 2] = v10;
          uvs[vIdx] = uv00;
          uvs[vIdx + 1] = uv01;
          uvs[vIdx + 2] = uv10;

          Vector3 n1 = (v01 - v00).cross(v10 - v00).normalized();
          if (flipFace) n1.negate();
          normals[vIdx] = normals[vIdx + 1] = normals[vIdx + 2] = n1;
          vIdx += 3;

          // Triangle 2: v01, v11, v10 (CCW)
          vertices[vIdx] = v01;
          vertices[vIdx + 1] = v11;
          vertices[vIdx + 2] = v10;
          uvs[vIdx] = uv01;
          uvs[vIdx + 1] = uv11;
          uvs[vIdx + 2] = uv10;

          Vector3 n2 = (v11 - v01).cross(v10 - v01).normalized();
          if (flipFace) n2.negate();
          normals[vIdx] = normals[vIdx + 1] = normals[vIdx + 2] = n2;
          vIdx += 3;
        }
      }

      final indices = (_vertexCount > 65535) ? Uint32List(numVert) : Uint16List(numVert);
      for (int k = 0; k < numVert; k++) {
        indices[k] = k;
      }
      _faceIndices.add(_M3Indices(WebGL.TRIANGLES, indices));

      // wireframe edges for flat mode
      _generateEdgeIndices(indices.toList());
    } else {
      // Smooth shading (original TRIANGLE_STRIP logic)
      int numVert = (widthSegments + 1) * (heightSegments + 1);
      _init(vertexCount: numVert, withNormals: true, withUV: true);

      final vertices = _vertices!;
      final uvs = _uvs!;
      final normals = _normals!;

      double x, y, z = 0;
      int i, j, index = 0;

      // vertices: position, texUV
      for (i = 0; i <= heightSegments; i++) {
        double ratioY = i.toDouble() / heightSegments;
        y = hy - height * ratioY;
        for (j = 0; j <= widthSegments; j++) {
          double ratioX = j.toDouble() / widthSegments;
          x = width * ratioX - hx;
          z = onVertex?.call(x, y) ?? 0;

          vertices[index] = transform(x, y, z);
          uvs[index] = Vector2(ratioX * uvScale.x, ratioY * uvScale.y);
          index++;
        }
      }

      // normals calculation for smooth mode (approximate face normals per vertex)
      index = 0;
      for (i = 0; i < heightSegments; i++) {
        for (j = 0; j <= widthSegments; j++) {
          Vector3 vn;
          if (j != widthSegments) {
            Vector3 dirX = vertices[index] - vertices[index + 1];
            Vector3 dirY = vertices[index] - vertices[index + widthSegments + 1];
            vn = dirY.cross(dirX).normalized();
            if (flipFace) vn.negate();
          } else {
            vn = normals[index - 1]; // end-dot same as previous
          }
          normals[index] = vn;
          index++;
        }
      }
      // normals end-line same as previous
      for (j = 0; j <= widthSegments; j++) {
        normals[index] = normals[index - widthSegments - 1];
        index++;
      }

      // solid: triangle-strip
      int numIndex = (widthSegments + 1) * 2 * (heightSegments) + 2 * (heightSegments - 1);
      if (flipFace) numIndex++;

      final indices = (_vertexCount > 65535) ? Uint32List(numIndex) : Uint16List(numIndex);
      index = 0;
      if (flipFace) {
        indices[0] = 0;
        index++;
      }

      for (i = 0; i < heightSegments; i++) {
        if (i > 0) {
          indices[index] = indices[index - 1]; // repeat prev-index
          indices[index + 1] = i * (widthSegments + 1); // repeat next-index
          index += 2;
        }
        for (j = 0; j <= widthSegments; j++) {
          indices[index] = i * (widthSegments + 1) + j;
          indices[index + 1] = indices[index] + (widthSegments + 1);
          index += 2;
        }
      }
      _faceIndices.add(_M3Indices(WebGL.TRIANGLE_STRIP, indices));

      // wireframe edges (original logic)
      int numWireIndex = ((widthSegments + 1) * heightSegments + widthSegments * (heightSegments + 1)) * 2;
      numWireIndex += widthSegments * 2; // extra slash lines

      final lines = (_vertexCount > 65535) ? Uint32List(numWireIndex) : Uint16List(numWireIndex);
      index = 0;
      for (i = 0; i <= heightSegments; i++) {
        for (j = 0; j < widthSegments; j++) {
          lines[index] = i * (widthSegments + 1) + j;
          lines[index + 1] = lines[index] + 1;
          index += 2;
        }
      }
      for (i = 0; i < heightSegments; i++) {
        for (j = 0; j <= widthSegments; j++) {
          lines[index] = i * (widthSegments + 1) + j;
          lines[index + 1] = lines[index] + (widthSegments + 1);
          index += 2;
        }
      }
      for (j = 1; j <= widthSegments; j++) {
        lines[index] = j;
        lines[index + 1] = lines[index] + widthSegments;
        index += 2;
      }
      _edgeIndices.add(_M3Indices(WebGL.LINES, lines));
    }

    _createVBO();
    localBounding.sphere.radius = Vector2(width, height).length / 2;
  }

  /// convert to height field
  M3HeightField toHeightField() {
    double x, y, z = 0;
    int i, j, index = 0;
    final numPoints = (widthSegments + 1) * (heightSegments + 1);
    final data = Float32List(numPoints);
    final hx = width * 0.5, hy = height * 0.5;

    // vertices: position
    for (j = 0; j <= widthSegments; j++) {
      double ratioX = j.toDouble() / widthSegments;
      x = width * ratioX - hx;
      //
      for (i = 0; i <= heightSegments; i++) {
        double ratioY = i.toDouble() / heightSegments;
        y = hy - height * ratioY;

        if (funcVertex != null) {
          z = funcVertex!(x, y);
        } else {
          z = 0;
        }

        data[index] = z;
        index++;
      }
    }

    final cellSize = Vector2(width / widthSegments, height / heightSegments);
    return M3HeightField(data, cellSize, 1.0);
  }
}
