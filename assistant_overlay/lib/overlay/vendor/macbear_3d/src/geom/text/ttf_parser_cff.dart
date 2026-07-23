// ignore_for_file: curly_braces_in_flow_control_structures, unused_local_variable, prefer_interpolation_to_compose_strings
part of 'ttf_parser.dart';

extension M3TrueTypeParserCff on M3TrueTypeParser {
  void _parseCFF2() {
    int offset = _tableOFFSETS['CFF2']!;
    M3Log.d('M3TrueTypeParser', 'Parsing CFF2 at file offset $offset. File length: ${_data.lengthInBytes}');

    // CFF2 Header (5 bytes)
    // uint8 major (2)
    // uint8 minor (0)
    // uint8 headerSize (5+)
    // uint16 topDictLength
    int headerSize = _data.getUint8(offset + 2);
    int topDictLength = _data.getUint16(offset + 3);
    M3Log.i('M3TrueTypeParser', 'CFF2 HeaderSize: $headerSize, TopDictLength: $topDictLength');

    String hHex = "";
    for (int i = 0; i < 16 && i < _data.lengthInBytes - offset; i++) {
      hHex += _data.getUint8(offset + i).toRadixString(16).padLeft(2, '0') + " ";
    }
    M3Log.d('M3TrueTypeParser', 'CFF2 Header HEX: $hHex');

    int topDictOffset = offset + headerSize;
    if (topDictOffset + topDictLength > _data.lengthInBytes) {
      M3Log.e('M3TrueTypeParser', 'Top DICT out of bounds!');
      return;
    }
    var topDict = _readDICT(topDictOffset, topDictLength, isCFF2: true);
    M3Log.d('M3TrueTypeParser', 'Top DICT keys: ${topDict.keys.toList()}');

    // Diagnostic: Dump Top DICT
    String tdHex = "";
    for (int i = 0; i < topDictLength; i++) {
      tdHex += _data.getUint8(topDictOffset + i).toRadixString(16).padLeft(2, '0') + " ";
    }
    M3Log.d('M3TrueTypeParser', 'Top DICT HEX: $tdHex');

    // Global Subrs (immediately follows Top DICT)
    int globalSubrsOffset = topDictOffset + topDictLength;
    if (globalSubrsOffset < _data.lengthInBytes) {
      M3Log.d('M3TrueTypeParser', 'Reading Global Subrs at file offset $globalSubrsOffset');
      // Diagnostic
      if (globalSubrsOffset + 4 <= _data.lengthInBytes) {
        int rawCount = _data.getUint32(globalSubrsOffset);
        M3Log.i('M3TrueTypeParser', 'Global Subrs raw 4-byte count: $rawCount');
      }
      _globalSubrs = _readINDEX(globalSubrsOffset, isCFF2: true);
      M3Log.i('M3TrueTypeParser', 'Global Subrs count: ${_globalSubrs.length}');
    }

    // CharStrings
    if (topDict.containsKey(17)) {
      // 17 is CharStrings offset in Top DICT
      var vals = topDict[17]!;
      if (vals.isNotEmpty) {
        int charStringsOffset = offset + vals[0].toInt();
        M3Log.d('M3TrueTypeParser', 'CharStrings at offset $charStringsOffset');
        _charStrings = _readINDEX(charStringsOffset, isCFF2: true);
        _numGlyphs = _charStrings.length;
        M3Log.i('M3TrueTypeParser', 'CharStrings count: ${_charStrings.length}');
      }
    }

    // Local Subrs (via FDArray/FDSelect for CID fonts, or Private DICT)
    if (topDict.containsKey(0x0C24)) {
      // FDArray (12 36)
      // ItemVariationStore (24)
      if (topDict.containsKey(24)) {
        int varStoreOffset = offset + topDict[24]![0].toInt();
        _parseVarStore(varStoreOffset);
      }

      var vals = topDict[0x0C24]!;
      if (vals.isNotEmpty) {
        int fdArrayOffset = offset + vals[0].toInt();
        M3Log.d('M3TrueTypeParser', 'FDArray at offset $fdArrayOffset');
        var fdArray = _readINDEX(fdArrayOffset, isCFF2: true);
        _fdArray = fdArray;
        M3Log.i('M3TrueTypeParser', 'FDArray count: ${_fdArray.length}');
        if (_fdArray.isNotEmpty) {
          M3Log.i('M3TrueTypeParser', 'FDArray parsed, count: ${_fdArray.length}. Subrs will be lazy loaded.');
        }
      }
    } else if (topDict.containsKey(18)) {
      // Simple Private DICT (non-CID)
      var vals = topDict[18]!;
      if (vals.isNotEmpty) {
        int privateSize = vals[0].toInt();
        int privateOffset = offset + vals[1].toInt();
        var privateDict = _readDICT(privateOffset, privateSize, isCFF2: true);
        if (privateDict.containsKey(19)) {
          var sVals = privateDict[19]!;
          if (sVals.isNotEmpty) {
            int localSubrsOffset = privateOffset + sVals[0].toInt();
            _localSubrs = _readINDEX(localSubrsOffset, isCFF2: true);
            M3Log.i('M3TrueTypeParser', 'Non-CID Local Subrs loaded: ${_localSubrs.length}');
          }
        }
      }
    }

    // Parse FDSelect if present
    if (topDict.containsKey(3109)) {
      int fdSelectOffset = offset + topDict[3109]![0].toInt();
      _parseFDSelect(fdSelectOffset);
    }

    // Store FDArray entries for later lookup
    if (topDict.containsKey(3108)) {
      int fdArrayOffset = offset + topDict[3108]![0].toInt();
      M3Log.d('M3TrueTypeParser', 'Reading FDArray at offset $fdArrayOffset (CFF2 format)');

      // Diagnostic: Dump FDArray header
      String fdaHex = "";
      for (int j = 0; j < 16; j++) {
        fdaHex += _data.getUint8(fdArrayOffset + j).toRadixString(16).padLeft(2, '0') + " ";
      }
      M3Log.d('M3TrueTypeParser', 'FDArray Header HEX: $fdaHex');

      _fdArray = _readINDEX(fdArrayOffset, isCFF2: true);
      M3Log.i('M3TrueTypeParser', 'FDArray count: ${_fdArray.length}');
    }
  }

  void _parseVarStore(int offset) {
    if (offset + 10 >= _data.lengthInBytes) return;
    // CFF2 Variation Store starts with a 2-byte length
    int vstoreLength = _data.getUint16(offset);
    int ivsOffset = offset + 2; // Standard ItemVariationStore follows length

    int format = _data.getUint16(ivsOffset);
    int regionListOffset = _data.getUint32(ivsOffset + 2) + ivsOffset;
    int itemVariationDataCount = _data.getUint16(ivsOffset + 6);
    M3Log.i(
      'M3TrueTypeParser',
      'CFF2 VarStore total length: $vstoreLength, format: $format, count=$itemVariationDataCount',
    );

    if (regionListOffset + 4 <= _data.lengthInBytes) {
      int axisCount = _data.getUint16(regionListOffset);
      int regionCount = _data.getUint16(regionListOffset + 2);
      M3Log.i('M3TrueTypeParser', 'CFF2 VarStore Config: Axes=$axisCount, Regions=$regionCount');
    }

    int pos = ivsOffset + 8;
    for (int i = 0; i < itemVariationDataCount; i++) {
      if (pos + 4 > _data.lengthInBytes) break;
      int ivdOffset = _data.getUint32(pos) + ivsOffset;
      pos += 4;

      if (ivdOffset + 6 <= _data.lengthInBytes) {
        int itemCount = _data.getUint16(ivdOffset);
        int shortDeltaCount = _data.getUint16(ivdOffset + 2);
        int regionIndexCount = _data.getUint16(ivdOffset + 4);
        M3Log.i(
          "M3TrueTypeParser",
          "IVD $i: itemCount=$itemCount, shortDeltaCount=$shortDeltaCount, regionIndexCount (k) = $regionIndexCount",
        );

        // k is the number of regions used by this IVD
        _regionIndexCounts[i] = regionIndexCount;
      }
    }
  }

  void _parseFDSelect(int offset) {
    if (offset >= _data.lengthInBytes) return;
    int format = _data.getUint8(offset);
    M3Log.d('M3TrueTypeParser', 'FDSelect format $format at $offset');
    if (format == 0) {
      for (int i = 0; i < _numGlyphs; i++) {
        if (offset + 1 + i < _data.lengthInBytes) {
          _fdSelect[i] = _data.getUint8(offset + 1 + i);
        }
      }
      M3Log.i('M3TrueTypeParser', 'FDSelect (Format 0) loaded for $_numGlyphs glyphs');
    } else if (format == 3) {
      int numRanges = _data.getUint16(offset + 1);
      int pos = offset + 3;
      int count = 0;
      for (int i = 0; i < numRanges; i++) {
        if (pos + 3 > _data.lengthInBytes) break;
        int first = _data.getUint16(pos);
        int fd = _data.getUint8(pos + 2);
        int nextFirst = _data.getUint16(pos + 3);
        for (int g = first; g < nextFirst; g++) {
          _fdSelect[g] = fd;
        }
        count += (nextFirst - first);
        pos += 3;
      }
      M3Log.i('M3TrueTypeParser', 'FDSelect (Format 3) loaded $count mappings (ranges: $numRanges)');
    }
  }

  List<Uint8List> _getLocalSubrsForGlyph(int glyphIndex) {
    int fdIndex = _fdSelect[glyphIndex] ?? 0;
    if (_fdLocalSubrs.containsKey(fdIndex)) return _fdLocalSubrs[fdIndex]!;

    if (fdIndex < _fdArray.length) {
      M3Log.i('M3TrueTypeParser', 'Loading Local Subrs for FD $fdIndex (Glyph $glyphIndex)...');
      var fontDict = _readDICT(0, 0, dataOverride: _fdArray[fdIndex], isCFF2: true);
      if (fontDict.containsKey(18)) {
        var pVals = fontDict[18]!;
        if (pVals.length >= 2) {
          int privateSize = pVals[0].toInt();
          int privateOffset = _tableOFFSETS['CFF2']! + pVals[1].toInt();
          M3Log.d('M3TrueTypeParser', 'Private DICT at $privateOffset (size $privateSize)');

          // Diagnostic: Dump Private DICT
          String pdHex = "";
          for (int j = 0; j < (privateSize < 64 ? privateSize : 64); j++) {
            pdHex += _data.getUint8(privateOffset + j).toRadixString(16).padLeft(2, '0') + " ";
          }
          M3Log.d('M3TrueTypeParser', 'Private DICT HEX: $pdHex');

          var privateDict = _readDICT(privateOffset, privateSize, isCFF2: true);

          if (privateDict.containsKey(19)) {
            int localSubrsOffset = privateOffset + privateDict[19]![0].toInt();
            var subrs = _readINDEX(localSubrsOffset, isCFF2: true);
            M3Log.d('M3TrueTypeParser', 'Local Subrs at $localSubrsOffset: count ${subrs.length}');
            _fdLocalSubrs[fdIndex] = subrs;
            return subrs;
          } else {
            M3Log.i('M3TrueTypeParser', 'No Local Subrs in Private DICT for FD $fdIndex');
            _fdLocalSubrs[fdIndex] = [];
            return [];
          }
        }
      }
    }

    // Fallback?
    if (fdIndex > 0) {
      M3Log.w(
        'M3TrueTypeParser',
        'Warning: No Local Subrs found for FD $fdIndex (Glyph $glyphIndex). Fallback to empty.',
      );
    }
    return _localSubrs;
  }

  List<Uint8List> _readINDEX(int fileOffset, {bool isCFF2 = false}) {
    if (fileOffset + (isCFF2 ? 5 : 3) > _data.lengthInBytes) {
      M3Log.e('M3TrueTypeParser', 'INDEX file offset out of bounds: $fileOffset');
      return [];
    }

    int count;
    int offSize;
    int pos;

    if (isCFF2) {
      // In CFF2, INDEX count is 4 bytes (Card32)
      count = _data.getUint32(fileOffset);
      offSize = _data.getUint8(fileOffset + 4);
      pos = fileOffset + 5;
    } else {
      // In CFF1, INDEX count is 2 bytes (Card16)
      count = _data.getUint16(fileOffset);
      if (count == 0) return [];
      offSize = _data.getUint8(fileOffset + 2);
      pos = fileOffset + 3;
    }

    if (count == 0 || count > 0x1000000) {
      // Safety cap
      if (count != 0) M3Log.e('M3TrueTypeParser', 'INDEX count too large or invalid: $count');
      return [];
    }

    if (offSize < 1 || offSize > 4) {
      M3Log.e('M3TrueTypeParser', 'INDEX invalid offSize: $offSize');
      return [];
    }
    int offsetArraySize = (count + 1) * offSize;
    if (pos + offsetArraySize > _data.lengthInBytes) {
      M3Log.e('M3TrueTypeParser', 'INDEX offset array out of bounds (pos $pos, size $offsetArraySize)');
      return [];
    }

    List<int> offsets = [];
    for (int i = 0; i <= count; i++) {
      int val = 0;
      for (int j = 0; j < offSize; j++) {
        val = (val << 8) | _data.getUint8(pos++);
      }
      offsets.add(val);
    }

    // The offsets are 1-based relative to the byte preceding the first data byte.
    // So dataStart = pos - 1.
    int dataBase = pos - 1;
    List<Uint8List> objects = [];

    for (int i = 0; i < count; i++) {
      int start = offsets[i];
      int end = offsets[i + 1];
      int len = end - start;

      if (len < 0) {
        M3Log.e('M3TrueTypeParser', 'INDEX invalid object length at $i: $len');
        continue;
      }

      int absoluteStart = dataBase + start;
      if (absoluteStart + len > _data.lengthInBytes) {
        M3Log.e(
          "M3TrueTypeParser",
          "INDEX object $i data out of bounds (absStart $absoluteStart, len $len, total ${_data.lengthInBytes})",
        );
        break;
      }

      if (len == 0) {
        objects.add(Uint8List(0));
      } else {
        // Create a copy to be safe and avoid view issues
        final bytes = Uint8List(len);
        for (int k = 0; k < len; k++) {
          bytes[k] = _data.getUint8(absoluteStart + k);
        }
        objects.add(bytes);
      }
    }
    return objects;
  }

  Map<int, List<double>> _readDICT(int offset, int length, {Uint8List? dataOverride, bool isCFF2 = false}) {
    Map<int, List<double>> dict = {};
    List<double> stack = [];
    int dictK = _regionIndexCounts[0] ?? 0;

    if (offset < 0 || (dataOverride == null && offset + length > _data.lengthInBytes)) {
      M3Log.e('M3TrueTypeParser', 'Invalid DICT range: offset $offset, length $length');
      return dict;
    }

    ByteData d;
    int start = 0;
    int end = 0;

    if (dataOverride != null) {
      if (dataOverride.isEmpty) return dict;
      d = ByteData.sublistView(dataOverride);
      start = 0;
      end = dataOverride.length;
    } else {
      d = _data;
      start = offset;
      end = offset + length;
    }

    int pos = start;
    while (pos < end) {
      int b0 = d.getUint8(pos++);
      if (b0 <= 27) {
        // CFF2 operators are 0-27
        int key = b0;
        if (b0 == 12) {
          if (pos >= end) break;
          key = (b0 << 8) | d.getUint8(pos++);
        }

        if (isCFF2) {
          if (key == 23) {
            // blend
            if (stack.isNotEmpty) {
              int n = stack.removeLast().toInt();
              int totalArgs = n + n * dictK;
              if (stack.length >= totalArgs) {
                // Simplified blend: keep default values
                List<double> defaults = stack.sublist(stack.length - totalArgs, stack.length - (n * dictK));
                stack.removeRange(stack.length - totalArgs, stack.length);
                stack.addAll(defaults);
              }
            }
            continue;
          } else if (key == 22) {
            // vsindex
            if (stack.isNotEmpty) {
              int ivs = stack.removeLast().toInt();
              dictK = _regionIndexCounts[ivs] ?? 0;
            }
            continue;
          }
        }

        dict[key] = List.from(stack);
        stack.clear();
      } else if (b0 == 28) {
        if (pos + 2 > end) {
          pos = end;
          break;
        }
        stack.add(d.getInt16(pos).toDouble());
        pos += 2;
      } else if (b0 == 29) {
        if (pos + 4 > end) {
          pos = end;
          break;
        }
        stack.add(d.getInt32(pos).toDouble());
        pos += 4;
      } else if (b0 == 30) {
        pos = _readReal(d, pos, end, stack);
      } else if (b0 >= 32 && b0 <= 246) {
        stack.add((b0 - 139).toDouble());
      } else if (b0 >= 247 && b0 <= 250) {
        if (pos >= end) {
          pos = end;
          break;
        }
        stack.add(((b0 - 247) * 256 + d.getUint8(pos++) + 108).toDouble());
      } else if (b0 >= 251 && b0 <= 254) {
        if (pos >= end) {
          pos = end;
          break;
        }
        stack.add((-(b0 - 251) * 256 - d.getUint8(pos++) - 108).toDouble());
      }
    }
    return dict;
  }

  int _readReal(ByteData d, int pos, int end, List<double> stack) {
    String s = "";
    bool terminated = false;
    while (pos < end && !terminated) {
      int b = d.getUint8(pos++);
      for (int i = 0; i < 2; i++) {
        int nibble = (i == 0) ? (b >> 4) : (b & 0x0F);
        if (nibble <= 9)
          s += nibble.toString();
        else if (nibble == 10)
          s += ".";
        else if (nibble == 11)
          s += "E";
        else if (nibble == 12)
          s += "E-";
        else if (nibble == 13) {
        } // reserved
        else if (nibble == 14)
          s += "-";
        else if (nibble == 15) {
          terminated = true;
          break;
        }
      }
    }
    if (s.isNotEmpty) {
      try {
        stack.add(double.parse(s));
      } catch (e) {
        M3Log.e('M3TrueTypeParser', 'Error parsing CFF real: $s');
      }
    }
    return pos;
  }

  List<List<Vector2>> _getGlyphContoursCFF(int glyphIndex, {int subdivisions = 4}) {
    if (glyphIndex >= _charStrings.length) {
      M3Log.e(
        'M3TrueTypeParser',
        'CFF: Glyph index $glyphIndex out of bounds for charStrings (length: ${_charStrings.length})',
      );
      return [];
    }
    Uint8List charString = _charStrings[glyphIndex];
    List<Uint8List> localSubrs = _getLocalSubrsForGlyph(glyphIndex);

    List<List<Vector2>> contours = [];

    // Debug: Dump CharString for analysis
    if (contours.isEmpty && glyphIndex > 0) {
      // Limit spam, maybe trigger on error?
      String hex = charString.take(50).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      M3Log.i('M3TrueTypeParser', 'Glyph $glyphIndex CharString Head: $hex');
      M3Log.i(
        'M3TrueTypeParser',
        'Local Subrs count: ${localSubrs.length}, Global Subrs count: ${_globalSubrs.length}',
      );
    }
    List<Vector2> currentContour = [];
    Vector2 currentPos = Vector2(0, 0);

    List<double> stack = [];
    double scale = 1.0 / _unitsPerEm;

    // TEMPORARY: Force k=0 to render static glyphs without variations.
    // This makes blend a no-op, keeping default values only.
    // Track stem hints for hintmask/cntrmask
    int numStemHints = 0;

    // Initial k from VarStore Data 0
    int k = _regionIndexCounts[0] ?? 0;

    void interpret(Uint8List data, {int depth = 0}) {
      if (depth > 20) {
        M3Log.i('M3TrueTypeParser', 'CFF CharString: Recursive call limit reached.');
        return;
      }
      int pos = 0;
      while (pos < data.length) {
        int b0 = data[pos++];
        if (glyphIndex == 63243) {
          M3Log.d('M3TrueTypeParser', '[CS Trace] pos ${pos - 1}: 0x${b0.toRadixString(16)} stack: $stack');
        }

        if (b0 >= 32) {
          double val;
          if (b0 <= 246) {
            val = (b0 - 139).toDouble();
          } else if (b0 <= 250) {
            val = ((b0 - 247) * 256 + data[pos++] + 108).toDouble();
          } else if (b0 <= 254) {
            val = (-(b0 - 251) * 256 - data[pos++] - 108).toDouble();
          } else {
            // 255
            final bd = ByteData.sublistView(data, pos, 4);
            val = bd.getInt32(0) / 65536.0;
            pos += 4;
          }
          stack.add(val);
          continue; // Operand pushed, next byte.
        }

        if (b0 == 28) {
          final bd = ByteData.sublistView(data, pos, 2);
          stack.add(bd.getInt16(0).toDouble());
          pos += 2;
          continue;
        }

        if (b0 == 10) {
          if (stack.isNotEmpty) {
            int subrIndex = stack.removeLast().toInt();
            int bias = localSubrs.length < 1240 ? 107 : (localSubrs.length < 33900 ? 1131 : 32768);
            int idx = subrIndex + bias;
            if (idx >= 0 && idx < localSubrs.length) {
              interpret(localSubrs[idx], depth: depth + 1);
            }
          }
          continue;
        }

        if (b0 == 29) {
          if (stack.isNotEmpty) {
            int subrIndex = stack.removeLast().toInt();
            int bias = _globalSubrs.length < 1240 ? 107 : (_globalSubrs.length < 33900 ? 1131 : 32768);
            int idx = subrIndex + bias;
            if (idx >= 0 && idx < _globalSubrs.length) {
              interpret(_globalSubrs[idx], depth: depth + 1);
            }
          }
          continue;
        }

        // Operator
        int op = b0;
        if (op == 12) {
          op = (12 << 8) | data[pos++];
        }

        if (op == 3094) {
          // vsindex (12 22)
          if (stack.isNotEmpty) {
            int ivs = stack.removeLast().toInt();
            k = _regionIndexCounts[ivs] ?? k;
            M3Log.i('M3TrueTypeParser', 'CFF CharString: vsindex set to $ivs (k=$k)');
          }
          continue;
        }

        if (op == 1 || op == 3 || op == 18 || op == 23) {
          numStemHints += stack.length ~/ 2;
          stack.clear();
          continue;
        }

        if (op == 19 || op == 20) {
          numStemHints += stack.length ~/ 2;
          stack.clear();
          if (numStemHints > 0) pos += (numStemHints + 7) ~/ 8;
          continue;
        }

        switch (op) {
          case 21: // rmoveto
            if (stack.length >= 2) {
              if (currentContour.isNotEmpty) contours.add(List.from(currentContour));
              currentContour = [];
              currentPos += Vector2(stack[stack.length - 2] * scale, stack[stack.length - 1] * scale);
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            } else {
              M3Log.i('M3TrueTypeParser', 'CFF CharString: rmoveto underflow at pos ${pos - 1}');
            }
            stack.clear();
            break;
          case 4: // vmoveto
            if (stack.isNotEmpty) {
              if (currentContour.isNotEmpty) contours.add(List.from(currentContour));
              currentContour = [];
              currentPos.y += stack.removeLast() * scale;
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            }
            stack.clear();
            break;
          case 22: // hmoveto
            if (stack.isNotEmpty) {
              if (currentContour.isNotEmpty) contours.add(List.from(currentContour));
              currentContour = [];
              currentPos.x += stack.removeLast() * scale;
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            }
            stack.clear();
            break;
          case 5: // rlineto
            for (int i = 0; i + 1 < stack.length; i += 2) {
              currentPos += Vector2(stack[i] * scale, stack[i + 1] * scale);
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            }
            stack.clear();
            break;
          case 6: // hlineto
          case 7: // vlineto
            bool horizontal = (op == 6);
            for (int i = 0; i < stack.length; i++) {
              if (horizontal)
                currentPos.x += stack[i] * scale;
              else
                currentPos.y += stack[i] * scale;
              currentContour.add(Vector2(currentPos.x, currentPos.y));
              horizontal = !horizontal;
            }
            stack.clear();
            break;
          case 8: // rrcurveto
            for (int i = 0; i + 5 < stack.length; i += 6) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1 = p0 + Vector2(stack[i] * scale, stack[i + 1] * scale);
              Vector2 p2 = p1 + Vector2(stack[i + 2] * scale, stack[i + 3] * scale);
              Vector2 p3 = p2 + Vector2(stack[i + 4] * scale, stack[i + 5] * scale);
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
            }
            stack.clear();
            break;
          case 24: // rcurveline
            int i = 0;
            for (; i + 5 < stack.length - 2; i += 6) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1 = p0 + Vector2(stack[i] * scale, stack[i + 1] * scale);
              Vector2 p2 = p1 + Vector2(stack[i + 2] * scale, stack[i + 3] * scale);
              Vector2 p3 = p2 + Vector2(stack[i + 4] * scale, stack[i + 5] * scale);
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
            }
            if (i + 1 < stack.length) {
              currentPos += Vector2(stack[i] * scale, stack[i + 1] * scale);
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            }
            stack.clear();
            break;
          case 25: // rlinecurve
            int i = 0;
            for (; i + 1 < stack.length - 6; i += 2) {
              currentPos += Vector2(stack[i] * scale, stack[i + 1] * scale);
              currentContour.add(Vector2(currentPos.x, currentPos.y));
            }
            if (i + 5 < stack.length) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1 = p0 + Vector2(stack[i] * scale, stack[i + 1] * scale);
              Vector2 p2 = p1 + Vector2(stack[i + 2] * scale, stack[i + 3] * scale);
              Vector2 p3 = p2 + Vector2(stack[i + 4] * scale, stack[i + 5] * scale);
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
            }
            stack.clear();
            break;
          case 26: // vvcurveto
            int i = 0;
            if (stack.length % 4 == 1) currentPos.x += stack[i++] * scale;
            for (; i + 3 < stack.length; i += 4) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1 = p0 + Vector2(0, stack[i] * scale);
              Vector2 p2 = p1 + Vector2(stack[i + 1] * scale, stack[i + 2] * scale);
              Vector2 p3 = p2 + Vector2(0, stack[i + 3] * scale);
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
            }
            stack.clear();
            break;
          case 27: // hhcurveto
            int i = 0;
            if (stack.length % 4 == 1) currentPos.y += stack[i++] * scale;
            for (; i + 3 < stack.length; i += 4) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1 = p0 + Vector2(stack[i] * scale, 0);
              Vector2 p2 = p1 + Vector2(stack[i + 1] * scale, stack[i + 2] * scale);
              Vector2 p3 = p2 + Vector2(stack[i + 3] * scale, 0);
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
            }
            stack.clear();
            break;
          case 30: // vhcurveto
          case 31: // hvcurveto
            bool verticalFirst = (op == 30);
            int i = 0;
            while (i + 3 < stack.length) {
              Vector2 p0 = Vector2(currentPos.x, currentPos.y);
              Vector2 p1, p2, p3;
              if (verticalFirst) {
                p1 = p0 + Vector2(0, stack[i++] * scale);
                p2 = p1 + Vector2(stack[i++] * scale, stack[i++] * scale);
                p3 = p2 + Vector2(stack[i++] * scale, 0);
                if (i == stack.length - 1) p3.y += stack[i++] * scale;
              } else {
                p1 = p0 + Vector2(stack[i++] * scale, 0);
                p2 = p1 + Vector2(stack[i++] * scale, stack[i++] * scale);
                p3 = p2 + Vector2(0, stack[i++] * scale);
                if (i == stack.length - 1) p3.x += stack[i++] * scale;
              }
              _addCubic(currentContour, p0, p1, p2, p3, subdivisions);
              currentPos = p3;
              verticalFirst = !verticalFirst;
            }
            stack.clear();
            break;
          case 11: // return
            return;
          case 14: // endchar
            if (currentContour.isNotEmpty) contours.add(List.from(currentContour));
            currentContour = [];
            stack.clear();
            return;
          case 16: // blend
            if (stack.isNotEmpty) {
              int n = stack.removeLast().toInt();
              int totalDeltas = n * k;
              M3Log.i('M3TrueTypeParser', 'CFF CharString: blend (n=$n, k=$k) stack size: ${stack.length}');
              if (stack.length < totalDeltas && n > 0) {
                // heuristic: if we have n + some deltas, maybe k is different
                int available = stack.length - n;
                if (available >= 0 && available % n == 0)
                  totalDeltas = available;
                else
                  totalDeltas = available > 0 ? available : 0;
              }
              if (stack.length >= totalDeltas) {
                stack.removeRange(stack.length - totalDeltas, stack.length);
              } else {
                stack.clear();
              }
            }
            break;
          default:
            stack.clear();
            break;
        }
      }
    }

    interpret(charString);
    if (currentContour.isNotEmpty) contours.add(List.from(currentContour));

    if (contours.isEmpty) return contours;

    return contours;
  }

  void _addCubic(List<Vector2> contour, Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, int subdivisions) {
    if (subdivisions <= 1) {
      contour.add(p3);
      return;
    }
    for (int s = 1; s <= subdivisions; s++) {
      double t = s / subdivisions;
      double invT = 1.0 - t;
      double tx = invT * invT * invT * p0.x + 3 * invT * invT * t * p1.x + 3 * invT * t * t * p2.x + t * t * t * p3.x;
      double ty = invT * invT * invT * p0.y + 3 * invT * invT * t * p1.y + 3 * invT * t * t * p2.y + t * t * t * p3.y;
      contour.add(Vector2(tx, ty));
    }
  }
}
