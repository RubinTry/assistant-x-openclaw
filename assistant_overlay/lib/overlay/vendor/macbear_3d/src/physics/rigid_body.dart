part of 'physics_engine.dart';

enum M3RigidBodyType { dynamic, fixed, kinematicPositionBased, kinematicVelocityBased }

/// Rigid body descriptor
class M3RigidBodyDesc {
  // world position (maps to Rapier translation)
  Vector3 position = Vector3.zero();
  Quaternion rotation = Quaternion.identity();

  Vector3 linearVelocity = Vector3.zero();
  Vector3 angularVelocity = Vector3.zero();

  double linearDamping = 0.0;
  double angularDamping = 0.0;

  M3RigidBodyType type;

  bool canSleep = true;
  bool ccdEnabled = false;

  M3RigidBodyDesc.dynamic() : type = M3RigidBodyType.dynamic;
  M3RigidBodyDesc.fixed() : type = M3RigidBodyType.fixed;
  M3RigidBodyDesc.kinematicPositionBased() : type = M3RigidBodyType.kinematicPositionBased;
  M3RigidBodyDesc.kinematicVelocityBased() : type = M3RigidBodyType.kinematicVelocityBased;
}

/// Abstract physics body for an entity.
abstract class M3RigidBody {
  int get handle;
  Vector3 get position;
  void setPosition(Vector3 position);

  Quaternion get rotation;
  void setRotation(Quaternion orientation);
}
