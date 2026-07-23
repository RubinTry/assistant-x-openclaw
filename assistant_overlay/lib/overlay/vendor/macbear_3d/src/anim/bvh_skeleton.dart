import 'dart:convert';

// Macbear3D engine
import '../m3_internal.dart';
import 'bvh_data.dart';
import 'bvh_parser.dart';

/// Visualizes a BVH skeleton using joint spheres and bone boxes.
class BvhSkeleton {
  final BvhData data;
  late final BvhAnimator animator;
  final Map<BvhJoint, M3Node> jointTransforms = {};
  final List<M3Entity> jointEntities = [];
  final List<M3Entity> boneEntities = [];
  final M3Node rootTransform = M3Node();

  static Future<BvhSkeleton> load(String path) async {
    final bytes = await M3ResourceManager.loadBuffer(path);
    final bvhString = utf8.decode(bytes.asUint8List());
    final bvhData = BvhParser.parse(bvhString);
    return BvhSkeleton(bvhData);
  }

  BvhSkeleton(this.data) {
    animator = BvhAnimator(data);
  }

  /// Creates entities and adds them to the scene.
  void addToScene(M3Scene scene) {
    _createHierarchy(data.root, rootTransform, scene);
  }

  void _createHierarchy(BvhJoint joint, M3Node? parentTransform, M3Scene scene) {
    final transform = M3Node();
    transform.parent = parentTransform;
    transform.position = joint.offset;
    jointTransforms[joint] = transform;

    // Joint visualization
    final jointEntity = scene.addMesh(M3Mesh(M3Resources.debugDot), Vector3.zero());
    jointEntity.color = Vector4(0, 1, 1, 1.0); // light-blue joints
    jointEntities.add(jointEntity);

    // Bone visualization (connect to parent)
    if (parentTransform != null) {
      final boneEntity = scene.addMesh(M3Mesh(M3Resources.unitBone), Vector3.zero());
      boneEntity.color = Vector4(1.0, 0.5, 0.0, 1.0); // Orange bones
      boneEntities.add(boneEntity);
    }

    for (final child in joint.children) {
      _createHierarchy(child, transform, scene);
    }
  }

  void update(double dt) {
    animator.update(dt, jointTransforms);
    _syncEntities();
  }

  void _syncEntities() {
    int jointIdx = 0;
    int boneIdx = 0;

    void syncRecursive(BvhJoint joint) {
      final transform = jointTransforms[joint]!;
      final worldMat = transform.worldMatrix;

      final jointEntity = jointEntities[jointIdx++];
      jointEntity.position = worldMat.getTranslation();
      jointEntity.rotation = Quaternion.fromRotation(worldMat.getRotation());
      jointEntity.scale = Vector3.all(0.3); // Better joint visibility

      for (final child in joint.children) {
        final childTransform = jointTransforms[child]!;
        final boneEntity = boneEntities[boneIdx++];

        final start = worldMat.getTranslation();
        final end = childTransform.worldMatrix.getTranslation();

        final center = (start + end) * 0.5;
        final dir = end - start;
        final len = dir.length;

        if (len > 0.001) {
          final forward = dir.normalized();
          boneEntity.position = center;
          boneEntity.rotation = Quaternion.fromTwoVectors(Vector3(1, 0, 0), forward);
          boneEntity.scale = Vector3(1, 0.25, 0.25) * len; // Thicker bones
        } else {
          boneEntity.scale = Vector3.all(0.0001); // Avoid singular matrix
        }

        syncRecursive(child);
      }
    }

    syncRecursive(data.root);
  }
}
