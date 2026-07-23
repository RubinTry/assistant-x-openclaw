// Macbear3D engine
import '../m3_internal.dart';
import '../renderer/shadow_map.dart';

part 'directional_light.dart';
part 'point_light.dart';
part 'spot_light.dart';

/// A directional or positional light source for scene illumination.
///
/// Extends [M3Camera] for shadow map rendering. Provides ambient and diffuse color blending.
abstract class M3Light {
  static Vector3 ambient = Vector3(0.2, 0.2, 0.2);
  Vector3 position = Vector3(0, 0, 6);
  Vector3 color = Colors.white.rgb - ambient;

  // shadow map
  bool castShadow = true;
  M3ShadowMap? shadowMap;

  /// set shadow map
  void setShadowMap(M3ShadowMap? sm) {
    shadowMap = sm;
    castShadow = sm != null;
  }

  static Vector4 blendRGBA(Vector4 a, Vector4 b) {
    return Vector4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w);
  }

  static Vector3 blendRGB(Vector3 a, Vector3 b) {
    return Vector3(a.x * b.x, a.y * b.y, a.z * b.z);
  }

  void drawHelper(M3Program prog, M3Camera viewer) {
    Matrix4 targetMatrix = Matrix4.identity();
    targetMatrix.setTranslation(position);
    targetMatrix.scaleByVector3(Vector3.all(0.1));
    prog.setMatrices(viewer, targetMatrix);
    M3Resources.debugPointLight.draw(prog);
  }
}

/// light manager
class M3PointLightManager {
  RenderingContext gl = M3AppEngine.instance.renderEngine.gl;

  static const int _maxLights = 8;
  static const int _maxShadow = 3;
  static const int _matCount = 4; // 8 點光源, 每 mat4 兩盞點光源

  final Float32List _lightMats = Float32List(_matCount * 16);
  final Int32List _counts = Int32List.fromList([0, 0]);
  int get lightCount => _counts[0];
  int get shadowCount => _counts[1];

  late UniformLocation _uniformPointLights;
  late UniformLocation _uniformPointLightCounts;

  List<M3PointLight> _pointLights = [];

  M3PointLightManager();

  void initLocation(Program program) {
    _uniformPointLights = gl.getUniformLocation(program, 'uPointLights');
    _uniformPointLightCounts = gl.getUniformLocation(program, 'uPointLightCounts');
  }

  void attachPointLights(List<M3PointLight> pointLights) {
    _pointLights = pointLights;
  }

  /// 每幀呼叫一次，lights 建議先經過 frustum/range culling 再傳入
  /// 內部強制排序（陰影燈優先），不信任外部呼叫端已排好順序
  void setLightUniforms(Matrix4 mMatrixInv) {
    final sorted = [..._pointLights];
    sorted.sort((a, b) {
      if (a.castShadow != b.castShadow) {
        return a.castShadow ? -1 : 1;
      }
      return 0;
    });

    final active = sorted.take(_maxLights).toList();

    int shadowCount = 0;
    for (final l in active) {
      if (l.castShadow && shadowCount < _maxShadow) {
        shadowCount++;
      }
    }

    _counts[0] = active.length;
    _counts[1] = shadowCount;

    _lightMats.fillRange(0, _lightMats.length, 0.0);

    for (int i = 0; i < lightCount && i < _maxLights; i++) {
      final packed = active[i].packBuffer(mMatrixInv);
      final matIndex = i ~/ 2;
      final localIndex = i % 2;
      final offset = matIndex * 16 + localIndex * 8;

      _lightMats.setRange(offset, offset + 8, packed);
    }

    if (M3Program.isLocationValid(_uniformPointLights)) {
      gl.uniformMatrix4fv(_uniformPointLights, false, _lightMats);
    }

    if (M3Program.isLocationValid(_uniformPointLightCounts)) {
      gl.uniform2iv(_uniformPointLightCounts, _counts);
    }
  }
}
