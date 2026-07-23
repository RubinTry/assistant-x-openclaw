part of 'shape_2d.dart';

/// A 2D rectangle shape with configurable position, size, and UV mapping.
class M3Rectangle2D extends M3Shape2D {
  double _rectW = 0;
  double _rectH = 0;

  M3Rectangle2D() : super(WebGL.TRIANGLE_STRIP, 4) {
    // set rectangle vertices
    setRectangle(0, 0, 16, 16);
  }

  @override
  String toString() {
    return '${super.toString()} ($_rectW x $_rectH)';
  }

  void setRectangle(double x, double y, double w, double h) {
    _rectW = w;
    _rectH = h;
    // set rectangle vertices
    _vertices[0] = Vector2(x, y);
    _vertices[1] = Vector2(x + w, y);
    _vertices[2] = Vector2(x, y + h);
    _vertices[3] = Vector2(x + w, y + h);

    // mapping UV (automatic 1:1 mapping by default)
    mappingUV(x, y, w, h);
  }

  // mapping texcoord-UV
  void mappingUV(double x, double y, double w, double h) {
    for (int i = 0; i < _vertexCount; i++) {
      double u = (_vertices[i].x - x) / w;
      double v = (_vertices[i].y - y) / h;
      _uvs[i] = Vector2(u, v);
    }
  }
}
