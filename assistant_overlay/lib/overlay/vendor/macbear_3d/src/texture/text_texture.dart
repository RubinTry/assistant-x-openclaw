part of 'texture.dart';

class M3TextTexture extends M3Texture {
  String text;
  TextStyle style;

  M3TextTexture._(this.text, {TextStyle? style})
    : style = style ?? const TextStyle(color: Color(0xFFFFFFFF), fontSize: 32, fontFamily: 'Arial'),
      super(useMipmaps: false) {
    name = "font(${this.style.fontSize}, ${this.style.fontFamily}): [$text]";
  }

  static Future<M3TextTexture> createFixed(String text, {int width = 256, int height = 256, TextStyle? style}) async {
    final tex = M3TextTexture._(text, style: style);
    tex.name = "createFixed: ${tex.name}";
    tex.texW = width;
    tex.texH = height;
    await tex._updateTexture();
    M3Log.i('M3TextTexture', tex.toString());
    return tex;
  }

  /// 更新文字內容
  Future<void> updateText(String newText) async {
    text = newText;
    await _updateTexture();
  }

  /// 內部生成貼圖像素並上傳 GPU
  Future<void> _updateTexture() async {
    // 使用 dart:ui Canvas 繪製文字
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, texW.toDouble(), texH.toDouble()));

    // 背景透明
    final paint = Paint()..color = const Color(0x00000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, texW.toDouble(), texH.toDouble()), paint);

    // 畫文字
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: texW.toDouble());
    textPainter.paint(canvas, Offset.zero);

    final picture = recorder.endRecording();
    final img = await picture.toImage(texW, texH);
    await loadTargetFromImage(img);
  }

  // size depends on text content
  static Future<M3TextTexture> createFromText(String text, {TextStyle? style}) async {
    final tex = M3TextTexture._(text, style: style);
    tex.name = "createFromText: ${tex.name}";
    await tex._createTextureFromLabel(text);
    M3Log.i('M3TextTexture', tex.toString());
    return tex;
  }

  Future<ui.Image> _makeLabelImage(
    String text, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final w = (textPainter.width + padding.horizontal).ceil();
    final h = (textPainter.height + padding.vertical).ceil();

    final bgPaint = Paint()..color = Colors.transparent;
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), bgPaint);

    textPainter.paint(canvas, Offset(padding.left, padding.top));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h);
    return img;
  }

  Future<void> _createTextureFromLabel(String text) async {
    final img = await _makeLabelImage(text);
    await loadTargetFromImage(img);
  }
}
