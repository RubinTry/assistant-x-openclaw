// Macbear3D engine
import '../m3_internal.dart';

/// Represents a single sub-mesh draw call data for sorting and batching.
class M3RenderItem {
  final M3Entity entity;
  final M3SubMesh subMesh;
  final Matrix4 worldMatrix;
  late Matrix4 worldMatrixInv;
  final double depth;
  List<M3PointLight> pointLights = [];

  M3RenderItem({required this.entity, required this.subMesh, required this.worldMatrix, required this.depth}) {
    worldMatrixInv = Matrix4.inverted(worldMatrix);
  }

  /// Priority for sorting opaque objects.
  /// Group by Material (program + texture) then by proximity.
  int get opaqueSortKey {
    // We could use program.id and texture.id if they were available
    // For now, we use material hash or just basic distance.
    return subMesh.mtr.renderOrder;
  }
}

/// A queue of render items to be processed in a specific order.
class M3RenderQueue {
  final List<M3RenderItem> items = [];

  void clear() => items.clear();

  void add(M3RenderItem item) => items.add(item);

  bool get isEmpty => items.isEmpty;

  /// Sort opaque items: Front-to-Back for Early-Z optimization.
  void sortOpaque() {
    items.sort((a, b) {
      // 1. User specified render order
      if (a.subMesh.mtr.renderOrder != b.subMesh.mtr.renderOrder) {
        return a.subMesh.mtr.renderOrder.compareTo(b.subMesh.mtr.renderOrder);
      }
      // 2. Proximity (Front-to-Back)
      return a.depth.compareTo(b.depth);
    });
  }

  /// Sort transparent items: Back-to-Front for correct alpha blending.
  void sortTransparent() {
    items.sort((a, b) {
      // 1. User specified render order
      if (a.subMesh.mtr.renderOrder != b.subMesh.mtr.renderOrder) {
        return a.subMesh.mtr.renderOrder.compareTo(b.subMesh.mtr.renderOrder);
      }
      // 2. Proximity (Back-to-Front)
      return b.depth.compareTo(a.depth);
    });
  }
}
