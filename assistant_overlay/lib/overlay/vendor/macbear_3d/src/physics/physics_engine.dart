import '../m3_internal.dart';

part 'collider.dart';
part 'rigid_body.dart';

/// Abstract physics engine interface.
abstract class M3PhysicsEngine {
  /// Initialize the physics engine.
  Future<void> init({Vector3? gravity});

  /// Dispose the physics engine.
  void dispose();

  /// Reset the physics engine.
  void resetWorld();

  /// create rigid body from descriptor
  M3RigidBody createRigidBody(M3RigidBodyDesc desc);

  /// remove rigid body
  void removeRigidBody(M3RigidBody body);

  /// create collider from descriptor
  M3Collider createCollider(M3RigidBody body, M3ColliderDesc desc);

  /// step simulation
  void step(double sec);

  String get info => "no physics info";
}
