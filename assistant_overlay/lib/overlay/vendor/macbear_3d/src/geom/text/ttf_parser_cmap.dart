// ignore_for_file: unused_local_variable
part of 'ttf_parser.dart';

extension M3TrueTypeParserCmap on M3TrueTypeParser {
  void _parseCmap() {
    int offset = _tableOFFSETS['cmap']!;
    int version = _data.getUint16(offset);
    int numberSubtables = _data.getUint16(offset + 2);

    int selectedOffset = 0;

    for (int i = 0; i < numberSubtables; i++) {
      int platformID = _data.getUint16(offset + 4 + i * 8);
      int encodingID = _data.getUint16(offset + 4 + i * 8 + 2);
      int subtableOffset = _data.getUint32(offset + 4 + i * 8 + 4);

      // Prefer Platform 3 (Windows), Encoding 1 (Unicode BMP) or 10 (Unicode full)
      // or Platform 0 (Unicode)
      if ((platformID == 3 && (encodingID == 1 || encodingID == 10)) || platformID == 0) {
        selectedOffset = offset + subtableOffset;
        break; // found a good table
      }
    }

    if (selectedOffset == 0 || selectedOffset + 2 > _data.lengthInBytes) return; // No supported cmap found

    int format = _data.getUint16(selectedOffset);
    if (format == 4) {
      _parseCmapFormat4(selectedOffset);
    } else if (format == 12) {
      _parseCmapFormat12(selectedOffset);
    }
    // Format 12 could be added here for full unicode support
  }

  void _parseCmapFormat4(int offset) {
    int length = _data.getUint16(offset + 2);
    int segCountX2 = _data.getUint16(offset + 6);
    int segCount = segCountX2 ~/ 2;

    // Arrays location
    int endCodeOffset = offset + 14;
    int startCodeOffset = endCodeOffset + segCountX2 + 2; // +2 for reservedPad
    int idDeltaOffset = startCodeOffset + segCountX2;
    int idRangeOffsetOffset = idDeltaOffset + segCountX2;

    List<int> endCodes = [];
    List<int> startCodes = [];
    List<int> idDeltas = [];
    List<int> idRangeOffsets = [];

    for (int i = 0; i < segCount; i++) {
      endCodes.add(_data.getUint16(endCodeOffset + i * 2));
      startCodes.add(_data.getUint16(startCodeOffset + i * 2));
      idDeltas.add(_data.getUint16(idDeltaOffset + i * 2)); // Signed? Usually treated as adding
      idRangeOffsets.add(_data.getUint16(idRangeOffsetOffset + i * 2));
    }

    // This is a naive full map expander for simplicity.
    // Ideally we'd look up on demand.
    // For this MVP let's store valid map entries.
    // But since this could be large, let's keep it empty and used look up logic if needed
    // or just pre-fill a limited range (e.g. ASCII).
    // Let's implement `getGlyphIndex` instead of pre-caching everything.

    // Storing data for lookup method
    _cmapFormat4Data = _CmapFormat4Data(segCount, endCodes, startCodes, idDeltas, idRangeOffsets, idRangeOffsetOffset);
  }

  void _parseCmapFormat12(int offset) {
    if (offset + 16 > _data.lengthInBytes) return;
    int numGroups = _data.getUint32(offset + 12);
    _cmapFormat12Data = [];
    for (int i = 0; i < numGroups; i++) {
      int groupOffset = offset + 16 + i * 12;
      if (groupOffset + 12 > _data.lengthInBytes) break;
      int start = _data.getUint32(groupOffset);
      int end = _data.getUint32(groupOffset + 4);
      int startGID = _data.getUint32(groupOffset + 8);
      _cmapFormat12Data!.add(_CmapGroup(start, end, startGID));
    }
  }

  int getGlyphIndex(int charCode) {
    if (_cmapFormat12Data != null) {
      for (var group in _cmapFormat12Data!) {
        if (charCode >= group.start && charCode <= group.end) {
          return group.startGID + (charCode - group.start);
        }
      }
    }
    if (_cmapFormat4Data == null) return 0;

    var data = _cmapFormat4Data!;
    for (int i = 0; i < data.segCount; i++) {
      if (data.endCodes[i] >= charCode) {
        if (data.startCodes[i] <= charCode) {
          if (data.idRangeOffsets[i] == 0) {
            return (charCode + data.idDeltas[i]) & 0xFFFF;
          } else {
            int ptr = data.idRangeOffsetOffset + i * 2 + data.idRangeOffsets[i]; // pointer to idRangeOffset[i]
            // offset from ptr
            int offset = (charCode - data.startCodes[i]) * 2;
            int glyphId = _data.getUint16(ptr + offset);
            if (glyphId != 0) {
              return (glyphId + data.idDeltas[i]) & 0xFFFF;
            }
            return 0;
          }
        } else {
          break; // Since endCodes are sorted
        }
      }
    }
    return 0;
  }
}

class _CmapFormat4Data {
  final int segCount;
  final List<int> endCodes;
  final List<int> startCodes;
  final List<int> idDeltas;
  final List<int> idRangeOffsets;
  final int idRangeOffsetOffset; // To calculate absolute address

  _CmapFormat4Data(
    this.segCount,
    this.endCodes,
    this.startCodes,
    this.idDeltas,
    this.idRangeOffsets,
    this.idRangeOffsetOffset,
  );
}

class _CmapGroup {
  final int start;
  final int end;
  final int startGID;
  _CmapGroup(this.start, this.end, this.startGID);
}
