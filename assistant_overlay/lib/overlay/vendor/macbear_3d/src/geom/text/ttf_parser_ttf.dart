// ignore_for_file: unused_local_variable
part of 'ttf_parser.dart';

extension M3TrueTypeParserTtf on M3TrueTypeParser {
  void _parseLoca() {
    int offset = _tableOFFSETS['loca']!;
    _locaTable = List.filled(_numGlyphs + 1, 0);

    for (int i = 0; i <= _numGlyphs; i++) {
      if (_indexToLocFormat == 0) {
        // Short version: offsets are divided by 2
        _locaTable[i] = _data.getUint16(offset + i * 2) * 2;
      } else {
        // Long version
        _locaTable[i] = _data.getUint32(offset + i * 4);
      }
    }
  }

  /// Reads glyph contours. Returns a list of loops (contours).
  /// Each loop is a list of Vector2 points.
  /// [subdivisions] is the number of segments for each Bezier curve.
  List<List<Vector2>> getGlyphContours(int glyphIndex, {int subdivisions = 4}) {
    if (_isOTF) {
      return _getGlyphContoursCFF(glyphIndex, subdivisions: subdivisions);
    }

    if (glyphIndex >= _locaTable.length - 1) return [];

    int offset = _tableOFFSETS['glyf']!;
    int glyphOffset = _locaTable[glyphIndex];
    int nextGlyphOffset = _locaTable[glyphIndex + 1];

    if (glyphOffset == nextGlyphOffset) {
      // Empty glyph (e.g. space)
      return [];
    }

    int fileOffset = offset + glyphOffset;
    if (fileOffset + 10 > _data.lengthInBytes) {
      // Check for glyph header bounds
      M3Log.e('M3TrueTypeParser', 'Glyph header out of bounds for glyph $glyphIndex at offset $fileOffset');
      return [];
    }

    // Glyph Header
    int numberOfContours = _data.getInt16(fileOffset);
    if (numberOfContours < 0) {
      // Compound glyph - NOT SUPPORTED in this minimal version
      M3Log.w('M3TrueTypeParser', 'Compound glyph $glyphIndex not supported.');
      return [];
    }

    fileOffset += 10;

    List<int> endPtsOfContours = [];
    for (int i = 0; i < numberOfContours; i++) {
      if (fileOffset + 2 > _data.lengthInBytes) {
        M3Log.e('M3TrueTypeParser', 'EndPtsOfContours read out of bounds for glyph $glyphIndex at offset $fileOffset');
        return [];
      }
      endPtsOfContours.add(_data.getUint16(fileOffset));
      fileOffset += 2;
    }

    if (fileOffset + 2 > _data.lengthInBytes) {
      M3Log.e('M3TrueTypeParser', 'InstructionLength read out of bounds for glyph $glyphIndex at offset $fileOffset');
      return [];
    }
    int instructionLength = _data.getUint16(fileOffset);
    if (fileOffset + 2 + instructionLength > _data.lengthInBytes) {
      M3Log.e(
        'M3TrueTypeParser',
        'Instructions out of bounds for glyph $glyphIndex at offset $fileOffset (length $instructionLength)',
      );
      return [];
    }
    fileOffset += 2 + instructionLength; // Skip instructions

    if (endPtsOfContours.isEmpty) {
      M3Log.w('M3TrueTypeParser', 'Glyph $glyphIndex has 0 contours but numberOfContours was $numberOfContours.');
      return [];
    }
    int numPoints = endPtsOfContours.last + 1;
    List<int> flags = [];
    int i = 0;
    while (i < numPoints) {
      if (fileOffset >= _data.lengthInBytes) {
        M3Log.e(
          'M3TrueTypeParser',
          'Flags read out of bounds for glyph $glyphIndex at offset $fileOffset (point $i/$numPoints)',
        );
        return [];
      }
      int flag = _data.getUint8(fileOffset++);
      flags.add(flag);
      i++;
      if ((flag & 8) != 0) {
        // Repeat flag
        if (fileOffset >= _data.lengthInBytes) {
          M3Log.e('M3TrueTypeParser', 'Repeat count read out of bounds for glyph $glyphIndex at offset $fileOffset');
          return [];
        }
        int repeatCount = _data.getUint8(fileOffset++);
        for (int r = 0; r < repeatCount; r++) {
          flags.add(flag);
          i++;
        }
      }
    }

    // Read Coords
    List<int> xCoords = [];
    int x = 0;
    for (int f in flags) {
      int dx = 0;
      if ((f & 2) != 0) {
        if (fileOffset >= _data.lengthInBytes) {
          M3Log.e(
            'M3TrueTypeParser',
            'X-coordinate byte read out of bounds for glyph $glyphIndex at offset $fileOffset',
          );
          return [];
        }
        int val = _data.getUint8(fileOffset++);
        dx = ((f & 16) != 0) ? val : -val;
      } else {
        if ((f & 16) == 0) {
          if (fileOffset + 2 > _data.lengthInBytes) {
            M3Log.e(
              'M3TrueTypeParser',
              'X-coordinate short read out of bounds for glyph $glyphIndex at offset $fileOffset',
            );
            return [];
          }
          dx = _data.getInt16(fileOffset);
          fileOffset += 2;
        }
      }
      x += dx;
      xCoords.add(x);
    }

    List<int> yCoords = [];
    int y = 0;
    for (int f in flags) {
      int dy = 0;
      if ((f & 4) != 0) {
        if (fileOffset >= _data.lengthInBytes) {
          M3Log.e(
            'M3TrueTypeParser',
            'Y-coordinate byte read out of bounds for glyph $glyphIndex at offset $fileOffset',
          );
          return [];
        }
        int val = _data.getUint8(fileOffset++);
        dy = ((f & 32) != 0) ? val : -val;
      } else {
        if ((f & 32) == 0) {
          if (fileOffset + 2 > _data.lengthInBytes) {
            M3Log.e(
              'M3TrueTypeParser',
              'Y-coordinate short read out of bounds for glyph $glyphIndex at offset $fileOffset',
            );
            return [];
          }
          dy = _data.getInt16(fileOffset);
          fileOffset += 2;
        }
      }
      y += dy;
      yCoords.add(y);
    }

    // Convert to contours
    List<List<Vector2>> contours = [];
    int startIndex = 0;
    double scale = 1.0 / _unitsPerEm; // Normalize to 1.0 height-ish

    for (int end in endPtsOfContours) {
      int endIndex = end;
      int count = endIndex - startIndex + 1;
      if (count < 2) {
        startIndex = endIndex + 1;
        continue;
      }

      List<Vector2> pts = [];
      List<bool> onCurve = [];
      for (int k = startIndex; k <= endIndex; k++) {
        if (k >= xCoords.length || k >= yCoords.length || k >= flags.length) {
          M3Log.e(
            "M3TrueTypeParser",
            "Coordinate or flag index out of bounds for glyph $glyphIndex at point $k (startIndex $startIndex, endIndex $endIndex)",
          );
          return []; // Critical error
        }
        pts.add(Vector2(xCoords[k] * scale, yCoords[k] * scale));
        onCurve.add((flags[k] & 1) != 0);
      }

      List<Vector2> contour = [];

      // Find first on-curve point
      int startIdx = -1;
      for (int k = 0; k < count; k++) {
        if (onCurve[k]) {
          startIdx = k;
          break;
        }
      }

      void addQuad(Vector2 p0, Vector2 p1, Vector2 p2) {
        if (subdivisions <= 1) {
          contour.add(p2);
          return;
        }
        for (int s = 1; s <= subdivisions; s++) {
          double t = s / subdivisions;
          double invT = 1.0 - t;
          double tx = invT * invT * p0.x + 2 * invT * t * p1.x + t * t * p2.x;
          double ty = invT * invT * p0.y + 2 * invT * t * p1.y + t * t * p2.y;
          contour.add(Vector2(tx, ty));
        }
      }

      if (startIdx == -1) {
        // All points are off-curve (uncommon but possible in some fonts)
        // Treat as a closed sequence of quadratics with midpoints as on-curve
        for (int k = 0; k < count; k++) {
          Vector2 p1 = pts[k];
          Vector2 p2 = (pts[k] + pts[(k + 1) % count]) * 0.5;
          Vector2 p0 = (pts[(k - 1 + count) % count] + pts[k]) * 0.5;
          addQuad(p0, p1, p2);
        }
      } else {
        // Rotate to start with on-curve point
        List<Vector2> rotatedPts = [];
        List<bool> rotatedOn = [];
        for (int k = 0; k < count; k++) {
          int idx = (startIdx + k) % count;
          rotatedPts.add(pts[idx]);
          rotatedOn.add(onCurve[idx]);
        }

        contour.add(rotatedPts[0]);
        for (int k = 1; k < count; k++) {
          if (rotatedOn[k]) {
            contour.add(rotatedPts[k]);
          } else {
            Vector2 p0 = contour.last;
            Vector2 p1 = rotatedPts[k];
            Vector2 p2;
            if (k + 1 < count && rotatedOn[k + 1]) {
              p2 = rotatedPts[k + 1];
              k++; // Skip next since it's the end of this cubic
            } else if (k + 1 < count) {
              // Consecutive off-curve points
              p2 = (rotatedPts[k] + rotatedPts[k + 1]) * 0.5;
              // Don't skip k+1, it's the control point for the next segment
            } else {
              // Last point is off-curve, connects back to start (which is on-curve)
              p2 = rotatedPts[0];
            }
            addQuad(p0, p1, p2);
          }
        }
        // Final edge back to start if needed (already handled by rotated logic mostly)
      }

      contours.add(contour);
      startIndex = endIndex + 1;
    }

    return contours;
  }
}
