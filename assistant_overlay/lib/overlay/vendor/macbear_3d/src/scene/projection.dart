part of 'camera.dart';

/// Manages projection matrix and viewport settings for perspective or orthographic rendering.
class M3Projection {
  static const int halfW = 8, halfH = 6;
  // matrix
  Matrix4 projectionMatrix = Matrix4.identity();
  // viewport: x,y,w,h
  int viewportX = -halfW, viewportY = -halfH;
  int viewportW = halfW * 2, viewportH = halfH * 2;
  // clip z-plane: near/far
  double nearClip = 1, farClip = 100.0;
  // Vertical Focus Of View by degree, zero means orthographic projection (parallel)
  double degreeFovY = 50.0;

  M3Projection() {
    refreshProjectionMatrix();
  }

  void setFrom(M3Projection other) {
    projectionMatrix.setFrom(other.projectionMatrix);
    viewportX = other.viewportX;
    viewportY = other.viewportY;
    viewportW = other.viewportW;
    viewportH = other.viewportH;
    nearClip = other.nearClip;
    farClip = other.farClip;
    degreeFovY = other.degreeFovY;
  }

  M3Projection clone() {
    return M3Projection()..setFrom(this);
  }

  // set viewport and projection matrix
  void setViewport(int x, int y, int w, int h, {double fovy = 50.0, double near = 1.0, double far = 100.0}) {
    viewportX = x;
    viewportY = y;
    viewportW = w;
    viewportH = h;

    degreeFovY = fovy;
    nearClip = near;
    farClip = far;
    refreshProjectionMatrix();
  }

  void enableInfinite() {
    if (degreeFovY > 0.0) {
      // perspective projection by infinitite far-clip
      double fovy = radians(degreeFovY);
      double aspect = (viewportW / viewportH).abs();
      projectionMatrix = makeInfiniteMatrix(fovy, aspect, nearClip);
    }
  }

  // refresh projection matrix
  void refreshProjectionMatrix() {
    if (degreeFovY > 0.0) {
      // perspective projection
      double fovy = radians(degreeFovY);
      double aspect = (viewportW / viewportH).abs();
      projectionMatrix = makePerspectiveMatrix(fovy, aspect, nearClip, farClip);
    } else {
      // orthographic projection (parallel)
      double viewW = viewportW.toDouble(); // default view width
      double viewH = viewportH.toDouble(); // default view height

      final left = viewportX.toDouble();
      final right = left + viewW;
      final bottom = viewportY.toDouble();
      final top = bottom + viewH;
      projectionMatrix = makeOrthographicMatrix(left, right, bottom, top, nearClip, farClip);
    }

    // Flip Y only for Metal/iOS
    // if (Platform.isIOS || Platform.isMacOS) {
    //   projectionMatrix.scaleByVector3(Vector3(1, -1, 1));
    // }
  }

  @override
  String toString() {
    return '''
Viewport: ($viewportX,$viewportY) - $viewportW x $viewportH
FovY: $degreeFovY, Clip Z: near=$nearClip, far=$farClip
''';
  }

  // convert eye-depth to frag-coord-Z(range: 0 ~ 1)
  double eyeDepthToFragZFromMatrix(double eyeDepth) {
    // [-1 ~ 1]
    // M22 = -(f + n) / (f - n); M32 = -2fn / (f - n)
    // M32 / D - M22 = (-2fn / D) / (f - n) + (f + n) / (f - n)
    //               = (f + n - 2fn / D) / (f - n)
    // D = f, result = (f + n - 2n) / (f - n) = (f - n) / (f - n) = 1
    // D = n, result = (f + n - 2f) / (f - n) = (n - f) / (f - n) = -1
    return (1 + projectionMatrix.entry(2, 3) / eyeDepth - projectionMatrix.entry(2, 2)) * 0.5;
  }

  // convert eye-depth to frag-coord-Z(range: 0 ~ 1)
  double eyeDepthToFragZFromNearFar(double eyeDepth) {
    return (1 + ((farClip + nearClip) - 2 * (farClip * nearClip) / eyeDepth) / (farClip - nearClip)) * .5;
  }
}
