import 'package:flutter/material.dart' hide Matrix4;
// Macbear3D engine
import '../m3_internal.dart' hide Colors;

/// ASCII text renderer using a monospaced font texture atlas.
class M3Text2D extends M3Sprite2D {
  static final firstChar = 32; // first char in ASCII table
  static final lastChar = 126; // last char in ASCII table
  static final String _ascii = List.generate(95, (i) {
    final char = String.fromCharCode(i + firstChar);
    return (i > 0 && i % 16 == 0) ? '\n$char' : char;
  }).join();

  M3Text2D(super.tex) : super(rowCount: 16, colCount: 6);

  static Future<M3Text2D> createText2D({double fontSize = 32}) async {
    // 'RobotoMono': 'assets/fonts/RobotoMono', 'Courier New': for windows
    TextStyle style = M3Package.textStyleRobotoMono(fontSize: fontSize);
    M3Texture tex = await M3TextTexture.createFromText(_ascii, style: style);
    M3Text2D text2D = M3Text2D(tex);

    return text2D;
  }

  void drawText(String text, Matrix4 mMatrix, {Vector4? color}) {
    Vector3 offset = Vector3.zero();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') {
        offset.x = 0;
        offset.y += spriteH;
      } else {
        final charIndex = char.codeUnitAt(0) - firstChar;
        final textMatrix = Matrix4.copy(mMatrix);
        textMatrix.translateByVector3(offset);

        // draw sprite by index
        super.draw(textMatrix, index: charIndex, color: color);
        offset.x += cellW;
      }
    }
  }
}
