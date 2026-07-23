import 'dart:convert';

// Macbear3D engine
import '../m3_internal.dart';
import 'gltf_parser.dart';

/// Loader for glTF and GLB 3D model files from assets or binary data.
///
/// This loader supports parsing the main glTF JSON structure, handling
/// embedded or external binary data (GLB), and loading associated textures.
class M3GltfLoader {
  /// Loads a glTF or GLB file from the assets folder.
  static Future<GltfDocument> load(String path) async {
    final bytes = await M3ResourceManager.loadBuffer(path);
    return loadFromBytes(bytes.asUint8List(), path);
  }

  /// Entry point for parsing glTF/GLB data from raw bytes.
  ///
  /// Automatically detects if the data is in binary GLB format via its [magic] header.
  static Future<GltfDocument> loadFromBytes(Uint8List bytes, String name) async {
    if (_isGlb(bytes)) {
      return _parseGlb(bytes, name);
    } else {
      // Treat as standard JSON-based glTF
      final jsonStr = utf8.decode(bytes);
      return _parseGltf(jsonStr, name, null);
    }
  }

  /// Checks for the GLB binary magic header ("glTF" in ASCII).
  static bool _isGlb(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final magic = bytes.buffer.asByteData().getUint32(0, Endian.little);
    return magic == 0x46546C67; // "glTF"
  }

  /// Parses the GLB binary format.
  ///
  /// GLB consists of a header followed by chunks.
  /// Chunk 0 is always JSON, Chunk 1 is typically binary data (BIN).
  static Future<GltfDocument> _parseGlb(Uint8List bytes, String name) async {
    final byteData = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);

    // GLB Header (12 bytes)
    // byte 0-3: magic (0x46546C67)
    // byte 4-7: version
    // byte 8-11: total length

    // --- Chunk 0: JSON ---
    final jsonChunkLength = byteData.getUint32(12, Endian.little);
    // byte 16-19: chunkType (0x4E4F534A -> JSON)
    final jsonBytes = bytes.sublist(20, 20 + jsonChunkLength);
    final jsonStr = utf8.decode(jsonBytes);

    // --- Chunk 1: BIN (optional) ---
    Uint8List? binData;
    final binChunkOffset = 20 + jsonChunkLength;
    if (binChunkOffset + 8 <= bytes.length) {
      final binChunkLength = byteData.getUint32(binChunkOffset, Endian.little);
      // byte +4: chunkType (0x004E4942 -> BIN)
      binData = bytes.sublist(binChunkOffset + 8, binChunkOffset + 8 + binChunkLength);
    }

    return _parseGltf(jsonStr, name, binData);
  }

  /// Parses the main glTF JSON structure and initializes resource loading.
  static Future<GltfDocument> _parseGltf(String jsonStr, String name, Uint8List? embeddedBin) async {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final doc = GltfDocument.parse(json, name, embeddedBin);

    // Load and initialize textures defined in the document
    final dir = name.contains('/') ? name.substring(0, name.lastIndexOf('/') + 1) : '';

    for (final texDef in doc.textures) {
      dynamic tex; // M3Texture?
      try {
        if (texDef.source != null && texDef.source! < doc.images.length) {
          final imgDef = doc.images[texDef.source!];

          if (imgDef.bufferView != null) {
            // Internal Reference: Load texture from a GLB bufferView
            final bytes = doc.getBufferViewData(imgDef.bufferView!);
            final texName = imgDef.name ?? '${name}_tex_${texDef.source}';
            tex = await M3Texture.createFromBytes(bytes, texName);
          } else if (imgDef.uri != null) {
            // External Reference: Load texture from a URI
            var uri = imgDef.uri!;
            if (!uri.startsWith('data:')) {
              // Path is relative to the glTF file
              final path = '$dir$uri';
              tex = await M3Texture.loadTexture(path);
            } else {
              // Data URI support (TODO: implement decoding if needed)
            }
          }
        }
      } catch (e) {
        // Silent fail for textures to allow model loading even if some textures fail
      }
      doc.runtimeTextures.add(tex);
    }

    return doc;
  }
}
