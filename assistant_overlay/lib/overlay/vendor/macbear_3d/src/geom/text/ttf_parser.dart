// ignore_for_file: unused_field, unused_local_variable, prefer_final_fields, prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

// Macbear3D engine
import '../../m3_internal.dart';

part 'ttf_parser_cmap.dart';
part 'ttf_parser_ttf.dart';
part 'ttf_parser_cff.dart';

/// A minimal TrueType (TTF) and OpenType (OTF) font parser to extract glyph paths for 3D reconstruction.
///
/// This parser extracts glyph outlines (contours) from font files and provides
/// them as sets of path commands for the geometry generators.
///
/// Key tables processed:
/// - `head`: Header info (units per EM, index to loc format).
/// - `maxp`: Maximum profile (number of glyphs).
/// - `loca`: Index to location (TTF only).
/// - `glyf`: Glyph data (TTF only).
/// - `cmap`: Character to glyph index mapping.
/// - `hmtx`: Horizontal metrics (advance widths).
/// - `CFF `/`CFF2`: PostScript outlines (OTF only).
class M3TrueTypeParser {
  /// The raw font file data.
  final ByteData _data;

  /// Offsets for various tables in the font file.
  final Map<String, int> _tableOFFSETS = {};

  int _numGlyphs = 0;
  int _unitsPerEm = 0;
  int _indexToLocFormat = 0; // 0 for short (16-bit), 1 for long (32-bit)

  List<int> _locaTable = [];
  Map<int, int> _cmap = {};
  List<double> _hMetrics = []; // Advance width for each glyph

  bool _isOTF = false;

  /// Returns true if the loaded font is in OpenType (CFF/CFF2) format.
  bool get isOTF => _isOTF;

  /// Returns true if the loaded font is in TrueType (glyf) format.
  bool get isTTF => !_isOTF;

  List<Uint8List> _charStrings = [];
  List<Uint8List> _globalSubrs = [];
  List<Uint8List> _localSubrs = [];

  _CmapFormat4Data? _cmapFormat4Data;
  List<_CmapGroup>? _cmapFormat12Data;

  Map<int, List<Uint8List>> _fdLocalSubrs = {};
  List<Uint8List> _fdArray = [];
  Map<int, int> _fdSelect = {}; // glyphIndex -> fdIndex
  Map<int, int> _regionIndexCounts = {}; // ivs -> regionIndexCount (k)

  /// Creates a font parser from raw [ByteData].
  M3TrueTypeParser(ByteData data) : _data = data {
    _parseFile();
  }

  /// Helper factory to load a font from a Flutter asset path.
  static Future<M3TrueTypeParser> loadFromAsset(String assetPath) async {
    final buffer = await M3ResourceManager.loadBuffer(assetPath);
    final data = buffer.asByteData();
    return M3TrueTypeParser(data);
  }

  /// Entry point for parsing the font file structure.
  void _parseFile() {
    try {
      _parseFileInternal();
    } catch (e, st) {
      M3Log.e('M3TrueTypeParser', 'FATAL ERROR: $e\n$st');
      rethrow;
    }
  }

  void _parseFileInternal() {
    // 1. Offset Table
    // uint32 scalerType: 'true' (0x74727565), 0x00010000, or 'OTTO' (0x4F54544F)
    if (_data.lengthInBytes < 12) {
      M3Log.e('M3TrueTypeParser', 'Font file too small: ${_data.lengthInBytes}');
      return;
    }
    int scalerType = _data.getUint32(0);
    _isOTF = (scalerType == 0x4F54544F);

    int numTables = _data.getUint16(4);
    M3Log.i('M3TrueTypeParser', 'Scaler Type: ${scalerType.toRadixString(16)}, Tables: $numTables');

    int offset = 12;
    for (int i = 0; i < numTables; i++) {
      if (offset + 16 > _data.lengthInBytes) break;
      String tag = _readTag(offset);
      int checkSum = _data.getUint32(offset + 4);
      int tableOffset = _data.getUint32(offset + 8);
      int length = _data.getUint32(offset + 12);
      M3Log.d('M3TrueTypeParser', 'Found table \'$tag\' at offset $tableOffset (length: $length)');
      _tableOFFSETS[tag] = tableOffset;
      offset += 16;
    }

    // 2. Head Table
    _parseHead();
    // 3. Maxp Table
    _parseMaxp();
    // 4. Loca Table (only for TTF)
    if (!_isOTF && _tableOFFSETS.containsKey('loca')) {
      _parseLoca();
    }
    // 5. Cmap Table (Character to Glyph Index mapping)
    if (_tableOFFSETS.containsKey('cmap')) {
      _parseCmap();
    }
    // 6. Hmtx Table (Horizontal Metrics)
    if (_tableOFFSETS.containsKey('hmtx')) {
      _parseHmtx();
    }

    // 7. CFF2 Table (for OTF)
    if (_isOTF && _tableOFFSETS.containsKey('CFF2')) {
      _parseCFF2();
    }
  }

  String _readTag(int offset) {
    List<int> chars = [];
    for (int i = 0; i < 4; i++) {
      chars.add(_data.getUint8(offset + i));
    }
    return String.fromCharCodes(chars);
  }

  void _parseHead() {
    int offset = _tableOFFSETS['head']!;
    _unitsPerEm = _data.getUint16(offset + 18);
    _indexToLocFormat = _data.getInt16(offset + 50);
  }

  void _parseMaxp() {
    int offset = _tableOFFSETS['maxp']!;
    _numGlyphs = _data.getUint16(offset + 4);
  }

  void _parseHmtx() {
    int offset = _tableOFFSETS['hmtx']!;
    int hheaOffset = _tableOFFSETS['hhea']!;
    int numberOfHMetrics = _data.getUint16(hheaOffset + 34);

    _hMetrics = [];
    for (int i = 0; i < numberOfHMetrics; i++) {
      int advanceWidth = _data.getUint16(offset + i * 4);
      // int lsb = _data.getInt16(offset + i * 4 + 2);
      _hMetrics.add(advanceWidth / _unitsPerEm);
    }
    // There are more LSb entries if numGlyphs > numberOfHMetrics, but we mainly need advanceWidth.
  }

  /// Returns the normalized advance width (based on unitsPerEm)
  double getAdvanceWidth(int glyphIndex) {
    if (glyphIndex >= _hMetrics.length) {
      if (_hMetrics.isNotEmpty) return _hMetrics.last;
      return 0.5; // fallback
    }
    return _hMetrics[glyphIndex];
  }
}
