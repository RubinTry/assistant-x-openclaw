part of '../geom.dart';

class M3TextGeom extends M3Geom {
  /// [text] is the string to render.
  /// [size] is the font size (scale factor).
  /// [depth] is the extrusion depth.
  /// [curveSubdivisions] is the number of segments for each Bezier curve.
  /// [creaseAngle] is the threshold angle (in degrees) for smoothing corners.
  M3TextGeom(
    String text,
    M3TrueTypeParser parser, {
    double size = 1.0,
    double depth = 0.2,
    int curveSubdivisions = 3,
    double creaseAngle = 40.0,
  }) {
    name = "TextGeom";

    // TTF by Quadratic Bezier curve, OTF by Cubic Bezier curve
    curveSubdivisions = max(parser.isTTF ? 1 : 2, curveSubdivisions);

    List<Vector3> allVertices = [];
    List<Vector3> allNormals = [];
    List<int> triIndices = []; // triangles
    List<int> lineIndices = []; // lines

    double cursorX = 0.0;
    double creaseCos = cos(creaseAngle * pi / 180.0);

    for (int i = 0; i < text.length; i++) {
      int charCode = text.codeUnitAt(i);

      if (charCode == 32) {
        // Space
        // we need advance width logic
        int glyphIndex = parser.getGlyphIndex(charCode);
        cursorX += parser.getAdvanceWidth(glyphIndex) * size;
        continue;
      }

      int glyphIndex = parser.getGlyphIndex(charCode);

      // Get contours
      List<List<Vector2>> contours = parser.getGlyphContours(glyphIndex, subdivisions: curveSubdivisions);
      if (contours.isEmpty) {
        cursorX += parser.getAdvanceWidth(glyphIndex) * size;
        continue;
      }

      // Use M3Contour for path classification and hierarchy
      M3Contour m3Contour = M3Contour(contours);
      if (m3Contour.infos.isEmpty) {
        cursorX += parser.getAdvanceWidth(glyphIndex) * size;
        continue;
      }

      // 3. Process each Outer island and its assigned holes
      for (int i = 0; i < m3Contour.normalizedOuters.length; i++) {
        var outer = m3Contour.normalizedOuters[i];
        var outerIdx = m3Contour.outerOrigIndices[i];
        List<List<Vector2>> triangulationHoles = [];

        for (int j = 0; j < m3Contour.normalizedHoles.length; j++) {
          var hIdx = m3Contour.holeOrigIndices[j];
          var holeInfo = m3Contour.infos.firstWhere((ti) => ti.index == hIdx);
          if (holeInfo.parent?.index == outerIdx) {
            triangulationHoles.add(m3Contour.normalizedHoles[j]);
          }
        }

        var triangulation = M3EarClipping.triangulate(outer, holes: triangulationHoles);
        List<Vector2> faceVertices = triangulation.vertices;
        List<int> localIndices = triangulation.indices;

        int indexOffset = allVertices.length;

        // Front Face (z = depth/2)
        for (var v in faceVertices) {
          allVertices.add(Vector3(cursorX + v.x * size, v.y * size, depth / 2));
          allNormals.add(Vector3(0, 0, 1));
        }
        for (int k = 0; k < localIndices.length; k += 3) {
          triIndices.add(indexOffset + localIndices[k]);
          triIndices.add(indexOffset + localIndices[k + 1]);
          triIndices.add(indexOffset + localIndices[k + 2]);
        }

        // Back Face (z = -depth/2)
        int backIndexOffset = allVertices.length;
        for (var v in faceVertices) {
          allVertices.add(Vector3(cursorX + v.x * size, v.y * size, -depth / 2));
          allNormals.add(Vector3(0, 0, -1));
        }
        // CW winding for back face results in CCW from the back
        for (int k = 0; k < localIndices.length; k += 3) {
          triIndices.add(backIndexOffset + localIndices[k]);
          triIndices.add(backIndexOffset + localIndices[k + 2]);
          triIndices.add(backIndexOffset + localIndices[k + 1]);
        }
      }

      // Extrusion (Sides)
      List<List<Vector2>> allContoursForSides = [...m3Contour.normalizedOuters, ...m3Contour.normalizedHoles];
      for (var contour in allContoursForSides) {
        int count = contour.length;
        if (count < 2) continue;

        // 1. Calculate edge normals
        List<Vector3> edgeNormals = [];
        for (int k = 0; k < count; k++) {
          Vector2 curr = contour[k];
          Vector2 next = contour[(k + 1) % count];
          Vector2 edge = next - curr;
          // Normal is (dy, -dx) for CCW loops to point outward.
          // For CW loops (holes), it will point inward.
          edgeNormals.add(Vector3(edge.y, -edge.x, 0).normalized());
        }

        // 2. Pre-calculate junction vertices
        List<List<int>> segmentStarts = List.generate(count, (_) => [-1, -1]);
        List<List<int>> segmentEnds = List.generate(count, (_) => [-1, -1]);

        for (int k = 0; k < count; k++) {
          int prevK = (k - 1 + count) % count;
          Vector3 nPrev = edgeNormals[prevK];
          Vector3 nCurr = edgeNormals[k];

          bool smooth = nPrev.dot(nCurr) > creaseCos;
          Vector3 sharedNormal = (nPrev + nCurr).normalized();

          if (smooth) {
            int fIdx = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, depth / 2));
            allNormals.add(sharedNormal);
            int bIdx = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, -depth / 2));
            allNormals.add(sharedNormal);
            segmentEnds[prevK] = [fIdx, bIdx];
            segmentStarts[k] = [fIdx, bIdx];
          } else {
            int fIn = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, depth / 2));
            allNormals.add(nPrev);
            int bIn = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, -depth / 2));
            allNormals.add(nPrev);
            segmentEnds[prevK] = [fIn, bIn];

            int fOut = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, depth / 2));
            allNormals.add(nCurr);
            int bOut = allVertices.length;
            allVertices.add(Vector3(cursorX + contour[k].x * size, contour[k].y * size, -depth / 2));
            allNormals.add(nCurr);
            segmentStarts[k] = [fOut, bOut];
          }
        }

        // 3. Generate side faces
        for (int k = 0; k < count; k++) {
          int sF = segmentStarts[k][0];
          int sB = segmentStarts[k][1];
          int eF = segmentEnds[k][0];
          int eB = segmentEnds[k][1];

          triIndices.add(sF);
          triIndices.add(sB);
          triIndices.add(eB);
          triIndices.add(sF);
          triIndices.add(eB);
          triIndices.add(eF);

          lineIndices.add(sF);
          lineIndices.add(eF);
          lineIndices.add(eF);
          lineIndices.add(eB);
          lineIndices.add(eB);
          lineIndices.add(sB);
          lineIndices.add(sB);
          lineIndices.add(sF);
        }
      }

      // Advance cursor
      cursorX += parser.getAdvanceWidth(glyphIndex) * size;
    }

    // Convert to buffers
    _init(vertexCount: allVertices.length, withNormals: true);
    for (int i = 0; i < allVertices.length; i++) {
      _vertices![i] = allVertices[i];
      _normals![i] = allNormals[i];
    }

    // vertex buffer object
    _createVBO();

    final indicesArray = (_vertexCount > 65535) ? Uint32List.fromList(triIndices) : Uint16List.fromList(triIndices);
    _faceIndices.add(_M3Indices(WebGL.TRIANGLES, indicesArray));

    // wireframe edges
    final edgesArray = (_vertexCount > 65535) ? Uint32List.fromList(lineIndices) : Uint16List.fromList(lineIndices);
    _edgeIndices.add(_M3Indices(WebGL.LINES, edgesArray));
  }
}
