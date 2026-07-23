// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unused_local_variable

// Macbear3D engine
import '../m3_internal.dart';

abstract class M3GL {
  /* Compressed Texture Format */
  static const int COMPRESSED_RGBA_ASTC_4x4_KHR = 0x93B0;
  static const int COMPRESSED_RGBA_ASTC_5x4_KHR = 0x93B1;
  static const int COMPRESSED_RGBA_ASTC_5x5_KHR = 0x93B2;
  static const int COMPRESSED_RGBA_ASTC_6x5_KHR = 0x93B3;
  static const int COMPRESSED_RGBA_ASTC_6x6_KHR = 0x93B4;
  static const int COMPRESSED_RGBA_ASTC_8x5_KHR = 0x93B5;
  static const int COMPRESSED_RGBA_ASTC_8x6_KHR = 0x93B6;
  static const int COMPRESSED_RGBA_ASTC_8x8_KHR = 0x93B7;
  static const int COMPRESSED_RGBA_ASTC_10x5_KHR = 0x93B8;
  static const int COMPRESSED_RGBA_ASTC_10x6_KHR = 0x93B9;
  static const int COMPRESSED_RGBA_ASTC_10x8_KHR = 0x93BA;
  static const int COMPRESSED_RGBA_ASTC_10x10_KHR = 0x93BB;
  static const int COMPRESSED_RGBA_ASTC_12x10_KHR = 0x93BC;
  static const int COMPRESSED_RGBA_ASTC_12x12_KHR = 0x93BD;

  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_4x4_KHR = 0x93D0;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_5x4_KHR = 0x93D1;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_5x5_KHR = 0x93D2;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_6x5_KHR = 0x93D3;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_6x6_KHR = 0x93D4;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_8x5_KHR = 0x93D5;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_8x6_KHR = 0x93D6;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_8x8_KHR = 0x93D7;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_10x5_KHR = 0x93D8;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_10x6_KHR = 0x93D9;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_10x8_KHR = 0x93DA;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_10x10_KHR = 0x93DB;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_12x10_KHR = 0x93DC;
  static const int COMPRESSED_SRGB8_ALPHA8_ASTC_12x12_KHR = 0x93DD;
}

class KtxInfo {
  final bool isKtx2;
  final int width;
  final int height;
  final int mipCount;
  final int vkFormat;
  final String formatName;
  final int glFormat;
  final Uint8List texData;

  KtxInfo({
    required this.isKtx2,
    required this.width,
    required this.height,
    required this.mipCount,
    required this.vkFormat,
    required this.formatName,
    required this.glFormat,
    required this.texData,
  });

  static Future<KtxInfo> parseKtx(String assetPath) async {
    final buffer = await M3ResourceManager.loadBuffer(assetPath);
    final ByteData data = buffer.asByteData();
    final u8List = buffer.asUint8List();
    final idAstc = Uint8List.fromList([0x13, 0xAB, 0xA1, 0x5C]);
    final idKtx = Uint8List.fromList([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]);
    final idKtx2 = Uint8List.fromList([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]);

    if (listEquals(u8List.sublist(0, 4), idAstc)) {
      return _parseAstc(data); // parse ASTC
    } else if (listEquals(u8List.sublist(0, 12), idKtx)) {
      return _parseKtx1(data); // parse KTX
    } else if (listEquals(u8List.sublist(0, 12), idKtx2)) {
      return _parseKtx2(data); // parse KTX2
    } else {
      throw Exception('Unsupported file extension: $assetPath');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// ASTC parser
// Magic number: 13 AB A1 5C
// ─────────────────────────────────────────────────────────────
KtxInfo _parseAstc(ByteData data) {
  final block_x = data.getUint8(0x04); // 4, 5, 6, 8, 10, 12
  final block_y = data.getUint8(0x05); // 4, 5, 6, 8, 10, 12
  final block_z = data.getUint8(0x06); // 1
  final dim_x = data.getUint16(0x07, Endian.little);
  final dim_y = data.getUint16(0x0A, Endian.little);
  final dim_z = data.getUint16(0x0D, Endian.little);
  final texData = data.buffer.asUint8List().sublist(16); // texture data
  int glInternalFormat = 0;

  if (block_x == 4 && block_y == 4) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_4x4_KHR;
  } else if (block_x == 6 && block_y == 6) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_6x6_KHR;
  } else if (block_x == 8 && block_y == 6) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_8x6_KHR;
  } else if (block_x == 8 && block_y == 8) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_8x8_KHR;
  } else if (block_x == 10 && block_y == 10) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_10x10_KHR;
  } else if (block_x == 12 && block_y == 12) {
    glInternalFormat = M3GL.COMPRESSED_RGBA_ASTC_12x12_KHR;
  } else {
    throw Exception('Unsupported ASTC block size: $block_x x $block_y');
  }

  final formatName = _glFormatName(glInternalFormat);

  return KtxInfo(
    isKtx2: false,
    width: dim_x,
    height: dim_y,
    mipCount: 1,
    vkFormat: glInternalFormat,
    formatName: formatName,
    glFormat: glInternalFormat,
    texData: texData,
  );
}

// ─────────────────────────────────────────────────────────────
// KTX1 parser
// KTX1 Header Structure (64 bytes)
// identifier(0): AB 4B 54 58 20 31 31 BB 0D 0A 1A 0A
// endianess(12): 0x04030201 indicates little-endian
// ─────────────────────────────────────────────────────────────
KtxInfo _parseKtx1(ByteData data) {
  // ─────────────────────────────────────────────
  // 驗證 magic number
  // ─────────────────────────────────────────────
  final magic = List.generate(12, (i) => data.getUint8(i));
  final isKtx = magic.toString() == [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A].toString();
  if (!isKtx) throw Exception('Invalid KTX1 magic number');

  // ─────────────────────────────────────────────
  // Header fields
  // ─────────────────────────────────────────────
  final endianness = data.getUint32(0x0C, Endian.little);
  final littleEndian = endianness == 0x04030201;
  final e = littleEndian ? Endian.little : Endian.big;

  final glType = data.getUint32(0x10, e);
  final glTypeSize = data.getUint32(0x14, e);
  final glFormat = data.getUint32(0x18, e);
  final glInternalFormat = data.getUint32(0x1C, e);
  final glBaseInternalFormat = data.getUint32(0x20, e);
  final pixelWidth = data.getUint32(0x24, e);
  final pixelHeight = data.getUint32(0x28, e);
  final pixelDepth = data.getUint32(0x2C, e);
  final numberOfArrayElements = data.getUint32(0x30, e);
  final numberOfFaces = data.getUint32(0x34, e);
  final numberOfMipmapLevels = data.getUint32(0x38, e);
  final bytesOfKeyValueData = data.getUint32(0x3C, e);

  // ─────────────────────────────────────────────
  // 第一個 image data 區塊 (level 0)
  // ─────────────────────────────────────────────
  int offset = 64 + bytesOfKeyValueData;
  final imageSize = data.getUint32(offset, e);
  offset += 4;

  // 拿出整個 block
  final full = data.buffer.asUint8List();
  final texData = full.sublist(offset, offset + imageSize);

  // 如果 imageSize 不是 4 byte 對齊，下一層會有 padding (這裡先忽略)
  // mipmapLevel 也可以在此循環讀取，但目前只取第 0 層。

  final formatName = _glFormatName(glInternalFormat);

  return KtxInfo(
    isKtx2: false,
    width: pixelWidth,
    height: pixelHeight,
    mipCount: numberOfMipmapLevels,
    vkFormat: glInternalFormat,
    formatName: formatName,
    glFormat: glInternalFormat,
    texData: texData,
  );
}

// ─────────────────────────────────────────────────────────────
// KTX2 parser
// KTX2 Header Structure (76 bytes)
// identifier: AB 4B 54 58 20 32 30 BB 0D 0A 1A 0A
// ─────────────────────────────────────────────────────────────
KtxInfo _parseKtx2(ByteData data) {
  // ─────────────────────────────────────────────
  // 驗證 magic number
  // ─────────────────────────────────────────────
  final magic = List.generate(12, (i) => data.getUint8(i));
  final validMagic =
      magic.toString() == [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A].toString();
  if (!validMagic) throw Exception('Invalid KTX2 magic number');

  final e = Endian.little;

  // ─────────────────────────────────────────────
  // Header fields
  // ─────────────────────────────────────────────
  final vkFormat = data.getUint32(0x0C, e);
  final typeSize = data.getUint32(0x10, e);
  final pixelWidth = data.getUint32(0x14, e);
  final pixelHeight = data.getUint32(0x18, e);
  final pixelDepth = data.getUint32(0x1C, e);
  final layerCount = data.getUint32(0x20, e);
  final faceCount = data.getUint32(0x24, e);
  final levelCount = data.getUint32(0x28, e);
  final supercompressionScheme = data.getUint32(0x2C, e);

  // offsets/sizes of sections
  final dfdByteOffset = data.getUint64(0x30, e);
  final dfdByteLength = data.getUint64(0x38, e);
  final kvdByteOffset = data.getUint64(0x40, e);
  final kvdByteLength = data.getUint64(0x48, e);
  final sgdByteOffset = data.getUint64(0x50, e);
  final sgdByteLength = data.getUint64(0x58, e);

  // Level Index table offset = immediately after the header (0x68)
  final levelIndexOffset = 0x68;
  final levels = <_Ktx2Level>[];

  for (int i = 0; i < (levelCount == 0 ? 1 : levelCount); i++) {
    final levelOffset = levelIndexOffset + i * 24;
    final byteOffset = data.getUint64(levelOffset, e);
    final byteLength = data.getUint64(levelOffset + 8, e);
    final uncompressedLength = data.getUint64(levelOffset + 16, e);
    levels.add(_Ktx2Level(byteOffset, byteLength, uncompressedLength));
  }

  if (levels.isEmpty) throw Exception('No level data found in KTX2');

  // ─────────────────────────────────────────────
  // 讀取 Level 0 的 tex data
  // ─────────────────────────────────────────────
  final level0 = levels.first;
  final full = data.buffer.asUint8List();
  final texData = full.sublist(level0.byteOffset.toInt(), level0.byteOffset.toInt() + level0.byteLength.toInt());

  final formatName = _vkFormatName(vkFormat);
  final glFormat = _mapVkToGL(vkFormat);

  // ─────────────────────────────────────────────
  // 返回解析資訊
  // ─────────────────────────────────────────────
  return KtxInfo(
    isKtx2: true,
    width: pixelWidth,
    height: pixelHeight,
    mipCount: levelCount == 0 ? 1 : levelCount,
    vkFormat: vkFormat,
    formatName: formatName,
    glFormat: glFormat,
    texData: texData,
  );
}

class _Ktx2Level {
  final int byteOffset;
  final int byteLength;
  final int uncompressedLength;
  _Ktx2Level(this.byteOffset, this.byteLength, this.uncompressedLength);
}

// ─────────────────────────────────────────────────────────────
// Format mapping helpers
// ─────────────────────────────────────────────────────────────
String _vkFormatName(int f) {
  const map = {
    157: 'ASTC_4x4_UNORM_BLOCK',
    162: 'ASTC_8x8_UNORM_BLOCK',
    147: 'ETC2_RGB8_UNORM_BLOCK',
    150: 'ETC2_RGBA8_UNORM_BLOCK',
    135: 'PVRTC1_4BPP_UNORM_BLOCK_IMG',
    70: 'BC1_RGB_UNORM_BLOCK',
    72: 'BC3_UNORM_BLOCK',
    79: 'BC7_UNORM_BLOCK',
    36: 'RGBA8_UNORM',
  };
  return map[f] ?? 'Unknown($f)';
}

String _glFormatName(int f) {
  const map = {
    M3GL.COMPRESSED_RGBA_ASTC_4x4_KHR: 'ASTC_4x4',
    M3GL.COMPRESSED_RGBA_ASTC_6x6_KHR: 'ASTC_6x6',
    M3GL.COMPRESSED_RGBA_ASTC_8x6_KHR: 'ASTC_8x6',
    M3GL.COMPRESSED_RGBA_ASTC_8x8_KHR: 'ASTC_8x8',
    M3GL.COMPRESSED_RGBA_ASTC_10x10_KHR: 'ASTC_10x10',
    M3GL.COMPRESSED_RGBA_ASTC_12x12_KHR: 'ASTC_12x12',
    0x9274: 'ETC2_RGB8',
    0x9278: 'ETC2_RGBA8',
    0x8C02: 'PVRTC1_4BPP',
    0x83F0: 'BC1',
    0x83F2: 'BC3',
    0x8E8C: 'BC7',
    0x1908: 'RGBA8',
  };
  return map[f] ?? 'Unknown($f)';
}

int _mapVkToGL(int vkFormat) {
  const vkToGL = {
    157: M3GL.COMPRESSED_RGBA_ASTC_4x4_KHR,
    162: M3GL.COMPRESSED_RGBA_ASTC_8x8_KHR,
    147: 0x9274, // ETC2 RGB8
    150: 0x9278, // ETC2 RGBA8
    135: 0x8C02, // PVRTC 4bpp
    70: 0x83F0, // BC1
    72: 0x83F2, // BC3
    79: 0x8E8C, // BC7
    36: 0x1908, // RGBA8
  };
  return vkToGL[vkFormat] ?? 0x93B0;
}
