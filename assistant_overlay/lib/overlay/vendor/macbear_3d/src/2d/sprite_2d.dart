// Macbear3D engine
import '../m3_internal.dart';

/// A 2D sprite with texture atlas support (row x column grid).
class M3Sprite2D {
  final M3Rectangle2D _rect = M3Rectangle2D();
  M3Material mtr = M3Material();

  late double spriteW;
  late double spriteH;

  late double cellW;
  late double cellH;

  // sample: row x col = (4 x 3)
  // 0 1 2 3
  // 4 5 6 7
  // 8 9 10 11
  int rowCount = 1;
  int colCount = 1;

  M3Sprite2D(M3Texture tex, {this.rowCount = 1, this.colCount = 1}) {
    mtr.diffuseTexture = tex;
    cellW = tex.texW.toDouble() / rowCount;
    cellH = tex.texH.toDouble() / colCount;

    spriteW = cellW;
    spriteH = cellH;

    if (rowCount > 1) {
      spriteW -= 1;
    }

    if (colCount > 1) {
      spriteH -= 1;
    }

    _rect.setRectangle(0, 0, spriteW, spriteH);
    _rect.mappingUV(0, 0, tex.texW.toDouble(), tex.texH.toDouble());
    _rect.createVBO(WebGL.STATIC_DRAW);
    M3Log.d('Sprite2D', _rect.toString());
  }

  void dispose() {
    mtr.diffuseTexture.dispose();
  }

  void draw(Matrix4 mMatrix, {int index = 0, Vector4? color}) {
    final row = index % rowCount;
    final col = (index ~/ rowCount) % colCount;

    final offsetX = row.toDouble() / rowCount;
    final offsetY = col.toDouble() / colCount;
    mtr.texMatrix[6] = offsetX;
    mtr.texMatrix[7] = offsetY;

    M3Shape2D.prog2D.setMaterial(mtr, color ?? Vector4(1, 1, 1, 1));
    M3Shape2D.prog2D.setModelMatrix(mMatrix);

    // draw shape2D
    _rect.draw();
  }
}
