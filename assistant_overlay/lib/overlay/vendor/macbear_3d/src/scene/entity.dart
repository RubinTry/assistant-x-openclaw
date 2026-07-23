// Macbear3D engine
import '../m3_internal.dart';

/// A scene entity representing a renderable object with transform and physics.
///
/// Combines a mesh, transform, color, and optional rigid body for physics simulation.
class M3Entity extends M3Node {
  M3RigidBody? rigidBody;
  final M3Mesh mesh;
  Vector4 color = Vector4(1.0, 1.0, 1.0, 1.0); // RGBA

  /// visibility culling
  M3Bounding worldBounding = M3Bounding();
  bool _boundsDirty = true;

  M3Entity({required this.mesh});

  M3ReflectionProbe? getProbe() {
    final renderEngine = M3AppEngine.instance.renderEngine;
    for (final probe in renderEngine.probes) {
      if (probe.owner == this) return probe;
    }
    return null;
  }

  /// Mark this entity as dirty, invalidating its world matrix and bounds.
  @override
  void markDirty() {
    super.markDirty();
    _boundsDirty = true;
  }

  /// Update the world bounding volume of this entity based on its mesh and transform.
  void updateBounds() {
    if (_boundsDirty && mesh.subMeshes.isNotEmpty) {
      final worldAabb = worldBounding.aabb;

      // Transform 8 corners of local AABB to world space
      worldAabb.min.setValues(double.infinity, double.infinity, double.infinity);
      worldAabb.max.setValues(double.negativeInfinity, double.negativeInfinity, double.negativeInfinity);

      for (final sub in mesh.subMeshes) {
        final localBounding = sub.geom.localBounding;
        final localAabb = localBounding.aabb;
        final matWorldSub = worldMatrix * mesh.initMatrix * sub.localMatrix;

        final v = Vector3.zero();
        for (int i = 0; i < 8; i++) {
          v.setValues(
            (i & 1) == 0 ? localAabb.min.x : localAabb.max.x,
            (i & 2) == 0 ? localAabb.min.y : localAabb.max.y,
            (i & 4) == 0 ? localAabb.min.z : localAabb.max.z,
          );
          matWorldSub.transform3(v);
          worldAabb.hullPoint(v);
        }
      }

      // If skin exists, also hull all bone world positions
      if (mesh.skin != null) {
        final v = Vector3.zero();
        for (int i = 0; i < mesh.skin!.boneCount; i++) {
          final jointNode = mesh.skin!.jointNodes![i];
          v.setFrom(jointNode.worldMatrix.getTranslation());
          worldMatrix.transform3(v); // Bring joint world to entity world
          worldAabb.hullPoint(v);
        }
      }

      // Update world sphere center from AABB center for simplicity in multi-submesh case
      worldBounding.sphere.center.setFrom(worldAabb.center);
      // radius: max distance from center to AABB corners
      worldBounding.sphere.radius = (worldAabb.max - worldAabb.min).length / 2;
      _boundsDirty = false;
    }
  }

  final Vector3 _prevPos = Vector3.zero();
  final Quaternion _prevRot = Quaternion.identity();

  void savePhysicsState() {
    if (rigidBody == null) return;
    _prevPos.setFrom(rigidBody!.position);
    _prevRot.setFrom(rigidBody!.rotation);
  }

  /// Synchronize the entity's transform from its physics rigid body using interpolation.
  void syncFromPhysics([double alpha = 1.0]) {
    if (rigidBody == null) return;

    final rbPos = rigidBody!.position;
    final rbRot = rigidBody!.rotation;

    // 1. Manual Lerp Position
    position.setValues(
      _prevPos.x + (rbPos.x - _prevPos.x) * alpha,
      _prevPos.y + (rbPos.y - _prevPos.y) * alpha,
      _prevPos.z + (rbPos.z - _prevPos.z) * alpha,
    );

    // 2. Manual Slerp Rotation
    double dot = _prevRot.x * rbRot.x + _prevRot.y * rbRot.y + _prevRot.z * rbRot.z + _prevRot.w * rbRot.w;

    final q2 = rbRot.clone();
    if (dot < 0.0) {
      q2.scale(-1.0);
      dot = -dot;
    }

    final lerpRot = Quaternion.identity();
    if (dot > 0.9995) {
      // NLerp
      lerpRot.setValues(
        _prevRot.x + (q2.x - _prevRot.x) * alpha,
        _prevRot.y + (q2.y - _prevRot.y) * alpha,
        _prevRot.z + (q2.z - _prevRot.z) * alpha,
        _prevRot.w + (q2.w - _prevRot.w) * alpha,
      );
    } else {
      double angle = acos(dot);
      double sinTotal = sin(angle);
      double ratioA = sin((1 - alpha) * angle) / sinTotal;
      double ratioB = sin(alpha * angle) / sinTotal;
      lerpRot.setValues(
        _prevRot.x * ratioA + q2.x * ratioB,
        _prevRot.y * ratioA + q2.y * ratioB,
        _prevRot.z * ratioA + q2.z * ratioB,
        _prevRot.w * ratioA + q2.w * ratioB,
      );
    }
    lerpRot.normalize();
    rotation = lerpRot;

    markDirty();
    _boundsDirty = true;
  }

  /// Synchronize the entity's transform to its physics rigid body.
  void syncToPhysics() {
    if (rigidBody == null) return;
    rigidBody!.setPosition(position);
    rigidBody!.setRotation(rotation);
  }

  void update(double dt) {
    // 1. Update Animator
    if (mesh.animator != null) {
      mesh.animator!.update(dt);
      _boundsDirty = true; // Animation moves joints, dirty the bounds
    }

    // Update submesh transforms for rigid node hierarchy animations
    mesh.updateSubMeshTransforms();

    // 2. Update Skin
    if (mesh.skin != null) {
      // In the current architecture, M3Entity represents the local space
      // for the mesh. We pass Identity as the MeshWorldMatrix because the
      // entity's matrix is applied later in the shader.
      mesh.skin!.update(null);
    }
  }

  M3Node get node => this;
}
