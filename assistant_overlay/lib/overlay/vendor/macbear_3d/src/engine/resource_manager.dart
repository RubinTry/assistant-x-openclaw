import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

// Macbear3D engine
import '../m3_internal.dart';

/// Manager responsible for loading, caching, and providing access to various engine resources.
///
/// It maintains registries for geometries, meshes, shaders, textures, and fonts to avoid
/// redundant loading and memory duplication.
class M3ResourceManager {
  /// Cache of loaded geometries.
  final Map<String, M3Geom> geoms = {};

  /// Cache of loaded meshes (geometry + material instances).
  final Map<String, M3Mesh> meshes = {};

  /// Cache of compiled shader programs.
  final Map<String, M3Program> programs = {};

  /// Cache of loaded textures.
  final Map<String, M3Texture> textures = {};

  /// Cache of parsed TrueType font instances.
  final Map<String, M3TrueTypeParser> fonts = {};

  /// Loads and caches a 3D mesh from the specified path.
  ///
  /// Supports both local asset paths and remote URLs.
  Future<M3Mesh> loadMesh(String path) async {
    if (meshes.containsKey(path)) {
      return meshes[path]!;
    }

    final mesh = await M3Mesh.load(path);
    meshes[path] = mesh;
    return mesh;
  }

  /// Loads and caches a TrueType font from the specified path.
  ///
  /// Supports both local asset paths and remote URLs. Returns an [M3TrueTypeParser]
  /// which can be used to generate font geometries.
  Future<M3TrueTypeParser> loadFont(String path) async {
    if (fonts.containsKey(path)) {
      return fonts[path]!;
    }

    // Centrally fetch raw bytes via loadBuffer
    final buffer = await loadBuffer(path);
    final parser = M3TrueTypeParser(buffer.asByteData());
    fonts[path] = parser;
    return parser;
  }

  /// Check if an asset exists
  ///
  /// Checks for both local assets (prefixed with 'assets/' or 'packages/')
  static Future<bool> isAssetExists(String assetPath) async {
    try {
      final fullPath = assetPath.startsWith('assets/') || assetPath.startsWith('packages/')
          ? assetPath
          : 'assets/$assetPath';
      await rootBundle.load(fullPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Core helper to fetch raw byte data as a [ByteBuffer] from a URL or local asset.
  ///
  /// Logic:
  /// 1. If [path] starts with 'http', it performs an HTTP GET request.
  /// 2. Otherwise, it treats [path] as a local asset and uses [rootBundle].
  ///
  /// This method is the primary portal for remote/local resource bridging.
  static Future<ByteBuffer> loadBuffer(String path) async {
    final isUrl = path.startsWith('http://') || path.startsWith('https://');

    if (isUrl) {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) {
        throw Exception('Failed to load data from URL ($path): ${response.statusCode}');
      }
      return response.bodyBytes.buffer;
    } else {
      // Asset path normalization: Ensure it starts with 'assets/' for rootBundle
      final fullPath = path.startsWith('assets/') || path.startsWith('packages/') ? path : 'assets/$path';
      final data = await rootBundle.load(fullPath);
      return data.buffer;
    }
  }

  /// Load image from path
  static Future<Image> loadImage(String path) async {
    final buffer = await loadBuffer(path);
    return createImageFromBytes(buffer.asUint8List());
  }

  /// Create image from byte buffer
  static Future<Image> createImageFromBytes(Uint8List bytes) async {
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
