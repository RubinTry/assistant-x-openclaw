part of 'physics_engine.dart';

enum M3ColliderShapeType { cuboid, ball, cylinder, cone, capsule, heightfield }

/// Collider descriptor
class M3ColliderDesc {
  final M3ColliderShapeType shapeType;

  // Dimensions
  double hx = 0, hy = 0, hz = 0; // cuboid (half-extents)
  double radius = 0; // ball, cylinder, cone, capsule
  double halfHeight = 0; // cylinder, cone, capsule

  // Common properties
  Vector3 localPosition = Vector3.zero();
  Quaternion localRotation = Quaternion.identity();

  double friction = 0.5;
  double restitution = 0.0;
  double density = 1.0;
  bool isSensor = false;

  M3ColliderDesc.cuboid(this.hx, this.hy, this.hz) : shapeType = M3ColliderShapeType.cuboid;
  M3ColliderDesc.ball(this.radius) : shapeType = M3ColliderShapeType.ball;
  M3ColliderDesc.cylinder(this.radius, this.halfHeight) : shapeType = M3ColliderShapeType.cylinder;
  M3ColliderDesc.cone(this.radius, this.halfHeight) : shapeType = M3ColliderShapeType.cone;
  M3ColliderDesc.capsule(this.radius, this.halfHeight) : shapeType = M3ColliderShapeType.capsule;
}

abstract class M3Collider {}
