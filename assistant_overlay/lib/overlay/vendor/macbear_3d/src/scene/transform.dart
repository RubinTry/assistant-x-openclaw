import 'package:vector_math/vector_math.dart';

/// Transform data for a node: position, rotation, scale
class M3Transform {
  Vector3 position = Vector3.zero();
  Quaternion rotation = Quaternion.identity();
  Vector3 scale = Vector3.all(1);

  Matrix4 get matrix => Matrix4.compose(position, rotation, scale);

  void setFrom(M3Transform other) {
    position.setFrom(other.position);
    rotation.setFrom(other.rotation);
    scale.setFrom(other.scale);
  }
}
