import '../m3_internal.dart';

/// No-op rigid body used when physics is disabled or not available
class M3NoRigidBody implements M3RigidBody {
  @override
  int get handle => 0;

  @override
  Vector3 get position => Vector3.zero();

  @override
  void setPosition(Vector3 position) {}

  @override
  Quaternion get rotation => Quaternion.identity();

  @override
  void setRotation(Quaternion rotation) {}
}

class M3NoCollider implements M3Collider {}

/// No-op physics engine used when physics is disabled or not available
class M3NoPhysicsEngine implements M3PhysicsEngine {
  @override
  Future<void> init({Vector3? gravity}) async {
    // do nothing
  }

  @override
  void dispose() {
    // do nothing
  }

  @override
  void resetWorld() {
    // do nothing
  }

  @override
  String get info => "no physics (disabled)";

  @override
  void step(double sec) {}

  @override
  M3Collider createCollider(M3RigidBody body, M3ColliderDesc desc) {
    return M3NoCollider();
  }

  @override
  M3RigidBody createRigidBody(M3RigidBodyDesc desc) {
    return M3NoRigidBody();
  }

  @override
  void removeRigidBody(M3RigidBody body) {}
}
