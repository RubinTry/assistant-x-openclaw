import 'package:vector_math/vector_math.dart';

/// Represents a joint in a BVH hierarchy.
class BvhJoint {
  final String name;
  final Vector3 offset;
  final List<String> channels;
  final List<BvhJoint> children;
  
  /// The index in the motion data row where this joint's channel values begin.
  int? channelOffset;

  BvhJoint({
    required this.name,
    required this.offset,
    required this.channels,
    this.children = const [],
    this.channelOffset,
  });

  bool get isEndSite => name == 'End Site';

  @override
  String toString() => 'BvhJoint($name, children: ${children.length})';
}

/// Represents the data parsed from a BVH file.
class BvhData {
  final BvhJoint root;
  final int frameCount;
  final double frameTime;
  
  /// All joints in a flattened list (depth-first order).
  final List<BvhJoint> allJoints;
  
  /// Motion data: frames x channel_values.
  final List<List<double>> frames;

  BvhData({
    required this.root,
    required this.frameCount,
    required this.frameTime,
    required this.allJoints,
    required this.frames,
  });

  double get duration => frameCount * frameTime;

  @override
  String toString() => 'BvhData(joints: ${allJoints.length}, frames: $frameCount, duration: ${duration.toStringAsFixed(2)}s)';
}
