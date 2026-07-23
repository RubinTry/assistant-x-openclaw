part of '../geom.dart';

/// Procedural terrain geometry using Perlin noise.
class M3TerrainGeom extends M3Geom {
  M3TerrainGeom(
    double width,
    double height, {
    int widthSegments = 64,
    int heightSegments = 64,
    double maxHeight = 5.0,
    double noiseScale = 0.05,
    int octaves = 4,
    Vector2? uvScale,
  }) : this._internal(
         width,
         height,
         (ratioX, ratioY, px, py) {
           double noiseVal = M3Noise.fBm(px * noiseScale, py * noiseScale, octaves: octaves);
           return noiseVal * maxHeight;
         },
         widthSegments: widthSegments,
         heightSegments: heightSegments,
         maxHeight: maxHeight,
         uvScale: uvScale,
       );

  M3TerrainGeom._internal(
    double width,
    double height,
    double Function(double ratioX, double ratioY, double px, double py) heightFunc, {
    int widthSegments = 64,
    int heightSegments = 64,
    double maxHeight = 5.0,
    Vector2? uvScale,
  }) {
    int numVert = (widthSegments + 1) * (heightSegments + 1);
    _init(vertexCount: numVert, withNormals: true, withUV: true);
    name = "Terrain";

    final vertices = _vertices!;
    final uvs = _uvs!;
    final normals = _normals!;
    uvScale = uvScale ?? Vector2(1, 1);

    int index = 0;
    final hx = width * 0.5, hy = height * 0.5;

    // 1. Generate vertices with heights
    for (int i = 0; i <= heightSegments; i++) {
      double ratioY = i.toDouble() / heightSegments;
      double py = hy - height * ratioY;
      for (int j = 0; j <= widthSegments; j++) {
        double ratioX = j.toDouble() / widthSegments;
        double px = width * ratioX - hx;

        double pz = heightFunc(ratioX, ratioY, px, py);

        vertices[index] = Vector3(px, py, pz);
        uvs[index] = Vector2(ratioX * uvScale.x, ratioY * uvScale.y);
        index++;
      }
    }

    // 2. Calculate normals for lighting
    for (int i = 0; i <= heightSegments; i++) {
      for (int j = 0; j <= widthSegments; j++) {
        int idx = i * (widthSegments + 1) + j;

        // simple normal estimation using adjacent vertices
        Vector3 v = vertices[idx];
        Vector3 vn = Vector3(0, 0, 1);

        if (i < heightSegments && j < widthSegments) {
          Vector3 vRight = vertices[idx + 1];
          Vector3 vDown = vertices[idx + (widthSegments + 1)];
          Vector3 dX = vRight - v;
          Vector3 dY = vDown - v;
          vn = dY.cross(dX).normalized();
        } else if (i > 0 && j > 0) {
          vn = normals[idx - (widthSegments + 1) - 1];
        } else if (i > 0) {
          vn = normals[idx - (widthSegments + 1)];
        } else if (j > 0) {
          vn = normals[idx - 1];
        }

        normals[idx] = vn;
      }
    }

    // 3. Generate indices (Triangle Strip)
    int numIndex = (widthSegments + 1) * 2 * (heightSegments) + 2 * (heightSegments - 1);
    final indices = (_vertexCount > 65535) ? Uint32List(numIndex) : Uint16List(numIndex);
    index = 0;
    for (int i = 0; i < heightSegments; i++) {
      if (i > 0) {
        indices[index] = indices[index - 1]; // repeat prev-index
        indices[index + 1] = i * (widthSegments + 1); // repeat next-index
        index += 2;
      }
      for (int j = 0; j <= widthSegments; j++) {
        indices[index++] = i * (widthSegments + 1) + j;
        indices[index++] = (i + 1) * (widthSegments + 1) + j;
      }
    }
    _faceIndices.add(_M3Indices(WebGL.TRIANGLE_STRIP, indices));

    // 4. Generate wireframe edges (LINES)
    int numWireIndex = ((widthSegments + 1) * heightSegments + widthSegments * (heightSegments + 1)) * 2;
    final lines = (_vertexCount > 65535) ? Uint32List(numWireIndex) : Uint16List(numWireIndex);
    index = 0;
    for (int i = 0; i <= heightSegments; i++) {
      for (int j = 0; j < widthSegments; j++) {
        // horizontal line
        lines[index++] = i * (widthSegments + 1) + j;
        lines[index++] = i * (widthSegments + 1) + j + 1;
      }
    }
    for (int i = 0; i < heightSegments; i++) {
      for (int j = 0; j <= widthSegments; j++) {
        // vertical line
        lines[index++] = i * (widthSegments + 1) + j;
        lines[index++] = (i + 1) * (widthSegments + 1) + j;
      }
    }
    _edgeIndices.add(_M3Indices(WebGL.LINES, lines));

    _createVBO();
    localBounding.sphere.radius = Vector3(hx, hy, maxHeight).length;
  }

  /// Create a terrain geometry from a [ui.Image] heightmap.
  static Future<M3TerrainGeom> fromHeightmapImage(
    ui.Image image,
    double width,
    double height, {
    int widthSegments = 64,
    int heightSegments = 64,
    double maxHeight = 5.0,
    Vector2? uvScale,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception("Failed to get raw RGBA bytes from heightmap image");
    }
    final pixels = byteData.buffer.asUint8List();
    final imgW = image.width;
    final imgH = image.height;

    final geom = M3TerrainGeom._internal(
      width,
      height,
      (ratioX, ratioY, px, py) {
        return _sampleHeight(pixels, imgW, imgH, ratioX, ratioY, maxHeight);
      },
      widthSegments: widthSegments,
      heightSegments: heightSegments,
      maxHeight: maxHeight,
      uvScale: uvScale,
    );
    geom.name = "TerrainFromHeightmap";
    return geom;
  }

  /// Create a terrain geometry from an asset path to a heightmap image.
  static Future<M3TerrainGeom> fromHeightmapAsset(
    String assetPath,
    double width,
    double height, {
    int widthSegments = 64,
    int heightSegments = 64,
    double maxHeight = 5.0,
    Vector2? uvScale,
  }) async {
    final buffer = await M3ResourceManager.loadBuffer(assetPath);
    final u8list = buffer.asUint8List();

    if (_is16BitPng(u8list)) {
      return from16BitPngBytes(
        u8list,
        width,
        height,
        widthSegments: widthSegments,
        heightSegments: heightSegments,
        maxHeight: maxHeight,
        uvScale: uvScale,
      );
    }

    final image = await M3ResourceManager.createImageFromBytes(u8list);
    return fromHeightmapImage(
      image,
      width,
      height,
      widthSegments: widthSegments,
      heightSegments: heightSegments,
      maxHeight: maxHeight,
      uvScale: uvScale,
    );
  }

  /// Detects if the PNG bytes represent a 16-bit image by inspecting the IHDR chunk.
  static bool _is16BitPng(Uint8List bytes) {
    if (bytes.length < 29) return false;
    // Check PNG signature: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47 ||
        bytes[4] != 0x0D ||
        bytes[5] != 0x0A ||
        bytes[6] != 0x1A ||
        bytes[7] != 0x0A) {
      return false;
    }
    // Check IHDR chunk type: "IHDR"
    if (bytes[12] != 0x49 || // I
        bytes[13] != 0x48 || // H
        bytes[14] != 0x44 || // D
        bytes[15] != 0x52) {
      // R
      return false;
    }
    int bitDepth = bytes[24];
    return bitDepth == 16;
  }

  /// Create a terrain geometry from 16-bit PNG bytes.
  static Future<M3TerrainGeom> from16BitPngBytes(
    Uint8List bytes,
    double width,
    double height, {
    int widthSegments = 64,
    int heightSegments = 64,
    double maxHeight = 5.0,
    Vector2? uvScale,
  }) async {
    final decoded = img.decodePng(bytes);
    if (decoded == null) {
      throw Exception("Failed to decode 16-bit PNG");
    }

    final geom = M3TerrainGeom._internal(
      width,
      height,
      (ratioX, ratioY, px, py) {
        return _sampleHeight16Bit(decoded, ratioX, ratioY, maxHeight);
      },
      widthSegments: widthSegments,
      heightSegments: heightSegments,
      maxHeight: maxHeight,
      uvScale: uvScale,
    );
    geom.name = "TerrainFrom16BitHeightmap";
    return geom;
  }

  static double _sampleHeight16Bit(img.Image image, double u, double v, double maxHeight) {
    final imgW = image.width;
    final imgH = image.height;
    // Bilinear interpolation for smooth height sample
    double px = u * (imgW - 1);
    double py = v * (imgH - 1);
    int x0 = px.floor().clamp(0, imgW - 1);
    int x1 = (x0 + 1).clamp(0, imgW - 1);
    int y0 = py.floor().clamp(0, imgH - 1);
    int y1 = (y0 + 1).clamp(0, imgH - 1);

    double tx = px - x0;
    double ty = py - y0;

    double h00 = _getPixelHeight16Bit(image, x0, y0);
    double h10 = _getPixelHeight16Bit(image, x1, y0);
    double h01 = _getPixelHeight16Bit(image, x0, y1);
    double h11 = _getPixelHeight16Bit(image, x1, y1);

    double h0 = h00 * (1.0 - tx) + h10 * tx;
    double h1 = h01 * (1.0 - tx) + h11 * tx;

    return (h0 * (1.0 - ty) + h1 * ty) * maxHeight;
  }

  static double _getPixelHeight16Bit(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    // Average RGB for grayscale elevation value, normalized by maxChannelValue
    return (pixel.r + pixel.g + pixel.b) / (3 * image.maxChannelValue);
  }

  static double _sampleHeight(Uint8List pixels, int imgW, int imgH, double u, double v, double maxHeight) {
    // Bilinear interpolation for smooth height sample
    double px = u * (imgW - 1);
    double py = v * (imgH - 1);
    int x0 = px.floor().clamp(0, imgW - 1);
    int x1 = (x0 + 1).clamp(0, imgW - 1);
    int y0 = py.floor().clamp(0, imgH - 1);
    int y1 = (y0 + 1).clamp(0, imgH - 1);

    double tx = px - x0;
    double ty = py - y0;

    double h00 = _getPixelHeight(pixels, imgW, x0, y0);
    double h10 = _getPixelHeight(pixels, imgW, x1, y0);
    double h01 = _getPixelHeight(pixels, imgW, x0, y1);
    double h11 = _getPixelHeight(pixels, imgW, x1, y1);

    double h0 = h00 * (1.0 - tx) + h10 * tx;
    double h1 = h01 * (1.0 - tx) + h11 * tx;

    return (h0 * (1.0 - ty) + h1 * ty) * maxHeight;
  }

  static double _getPixelHeight(Uint8List pixels, int imgW, int x, int y) {
    int idx = (y * imgW + x) * 4;
    if (idx >= pixels.length) return 0.0;
    int r = pixels[idx];
    int g = pixels[idx + 1];
    int b = pixels[idx + 2];
    // Average RGB for grayscale elevation value
    return (r + g + b) / 765.0; // 3 * 255
  }
}
