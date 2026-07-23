import 'package:vector_math/vector_math_lists.dart';

// Macbear3D engine
import '../m3_internal.dart';

// part for shape2D
part 'rectangle_2d.dart';

/// Base class for 2D shapes with dynamic vertex buffers for lines, triangles, and images.
class M3Shape2D {
  RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;
  static M3Program get prog2D => M3Resources.programRectangle!;

  // always GL_TRIANGLES, GL_TRIANGLE_STRIP, GL_LINES, GL_LINE_STRIP
  // not supported: GL_TRIANGLE_FAN, GL_LINE_LOOP
  final int _primitiveType;
  final int _vertexCount;

  late int _usage; // usage for VBO: dynamic is slower, be careful to use it
  late Vector2List _vertices; // vertex positions
  late Vector2List _uvs; // vertex texture coordinates(u,v)

  // VBO: vertex buffer object
  Buffer? _vertexBuffer;
  Buffer? _uvBuffer;

  static M3Material mtrWhite = M3Material();

  M3Shape2D(this._primitiveType, this._vertexCount) {
    // call init with vertex count
    _vertices = Vector2List(_vertexCount);
    _uvs = Vector2List(_vertexCount);

    // createVBO();
  }

  @override
  String toString() {
    final drawUsage = _usage == WebGL.STATIC_DRAW ? 'STATIC_DRAW' : 'DYNAMIC_DRAW';
    return 'M3Shape2D{Count: $_vertexCount, $drawUsage}';
  }

  // create vertex buffer object: static or dynamic
  // dynamic is slower, be careful to use it
  void createVBO(int usage) {
    _usage = usage;
    // buffers for vertices, normals after init
    _vertexBuffer = gl.createBuffer();
    gl.bindBuffer(WebGL.ARRAY_BUFFER, _vertexBuffer);
    gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_vertices.buffer), usage);

    _uvBuffer = gl.createBuffer();
    gl.bindBuffer(WebGL.ARRAY_BUFFER, _uvBuffer);
    gl.bufferData(WebGL.ARRAY_BUFFER, toF32List(_uvs.buffer), usage);
  }

  void dispose() {
    if (_vertexBuffer != null) {
      gl.deleteBuffer(_vertexBuffer!);
      _vertexBuffer = null;
    }
    if (_uvBuffer != null) {
      gl.deleteBuffer(_uvBuffer!);
      _uvBuffer = null;
    }
  }

  void draw() {
    // bind vertex buffer
    gl.bindBuffer(WebGL.ARRAY_BUFFER, _vertexBuffer);
    if (_usage != WebGL.STATIC_DRAW) {
      gl.bufferSubData(WebGL.ARRAY_BUFFER, 0, toF32List(_vertices.buffer));
    }
    gl.vertexAttribPointer(prog2D.attribVertex.id, 2, WebGL.FLOAT, false, 0, 0);

    gl.bindBuffer(WebGL.ARRAY_BUFFER, _uvBuffer);
    if (_usage != WebGL.STATIC_DRAW) {
      gl.bufferSubData(WebGL.ARRAY_BUFFER, 0, toF32List(_uvs.buffer));
    }
    gl.vertexAttribPointer(prog2D.attribUV.id, 2, WebGL.FLOAT, false, 0, 0);

    // draw call
    gl.drawArrays(_primitiveType, 0, _vertices.length);

    gl.bindBuffer(WebGL.ARRAY_BUFFER, null);
  }

  // dynamic draw line
  static void drawLine(Vector2 pt0, Vector2 pt1, Vector4 color) {
    prog2D.setMaterial(M3Shape2D.mtrWhite, color);

    // set line vertices
    final line = M3Resources.line;
    line._vertices[0] = pt0;
    line._vertices[1] = pt1;

    // draw shape2D
    line.draw();
  }

  // dynamic draw triangle
  static void drawTriangle(Vector2 pt0, Vector2 pt1, Vector2 pt2, Vector4 color) {
    prog2D.setMaterial(M3Shape2D.mtrWhite, color);

    // set triangle vertices
    final tri = M3Resources.triangle;
    tri._vertices[0] = pt0;
    tri._vertices[1] = pt1;
    tri._vertices[2] = pt2;

    // draw shape2D
    tri.draw();
  }

  static void drawImage(M3Texture tex, Matrix4 mMatrix, {Vector4? color}) {
    Vector4 imgColor = Colors.white;
    if (color != null) {
      imgColor = color;
    }
    M3Material mtr = M3Material();
    mtr.diffuseTexture = tex;

    Matrix4 imgMatrix = mMatrix.clone();
    imgMatrix.scaleByVector3(Vector3(tex.texW.toDouble(), tex.texH.toDouble(), 1));

    M3Shape2D.prog2D.setMaterial(mtr, imgColor);
    M3Shape2D.prog2D.setModelMatrix(imgMatrix);

    // draw shape2D
    M3Resources.rectUnit.draw();
  }

  static void drawTouches(M3TouchManager manager) {
    final colors = [
      Vector4(1, 0, 0, 1), // 0x01: left
      Vector4(0, 1, 0, 1), // 0x02: right
      Vector4(1, 1, 0, 1), // 0x03: left + right
      Vector4(0, 0, 1, 1), // 0x04: middle
      Vector4(1, 0, 1, 1), // 0x05: left + middle
      Vector4(0, 1, 1, 1), // 0x06: right + middle
      Vector4(1, 1, 1, 1), // 0x07: left + middle + right
    ];
    manager.touches.forEach((id, touch) {
      if (touch.path.length < 2) return;
      Vector2 pt0, pt1;

      pt0 = touch.path[0].position;
      drawTriangle(pt0, pt0 + Vector2(0, -20), pt0 + Vector2(-9, -15), Vector4(0.7, 0.3, 0.7, 1));

      for (int i = 0; i < touch.path.length - 1; i++) {
        pt0 = touch.path[i].position;
        pt1 = touch.path[i + 1].position;
        final index = (touch.path[i].buttons - 1) % 7;
        drawLine(pt0, pt1, colors[index]);
      }

      pt1 = touch.path[touch.path.length - 1].position;
      drawTriangle(pt1, pt1 + Vector2(0, -20), pt1 + Vector2(-9, -15), Vector4(0.7, 0.7, 0.3, 1));
    });
  }
}
