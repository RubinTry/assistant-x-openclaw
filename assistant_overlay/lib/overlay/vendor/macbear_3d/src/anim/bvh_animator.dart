// Macbear3D engine
import '../m3_internal.dart';
import 'bvh_data.dart';

/// Handles playback and interpolation of BVH motion data.
class BvhAnimator {
  final BvhData data;
  double _time = 0;
  bool isPlaying = true;
  bool loop = true;
  double speed = 1.0;

  BvhAnimator(this.data);

  void update(double dt, Map<BvhJoint, M3Node> jointTransforms) {
    if (!isPlaying || data.frameCount == 0) return;

    _time += dt * speed;
    if (loop) {
      _time %= data.duration;
    } else if (_time > data.duration) {
      _time = data.duration;
      isPlaying = false;
    }

    final frameIndex = (_time / data.frameTime).floor();
    final nextFrameIndex = (frameIndex + 1) % data.frameCount;
    final t = (_time % data.frameTime) / data.frameTime;

    final currentFrame = data.frames[frameIndex];
    final nextFrame = data.frames[nextFrameIndex];

    for (final joint in data.allJoints) {
      final transform = jointTransforms[joint];
      if (transform == null || joint.channelOffset == null) continue;

      _applyJointAnimation(joint, transform, currentFrame, nextFrame, t);
    }
  }

  void _applyJointAnimation(BvhJoint joint, M3Node transform, List<double> frame1, List<double> frame2, double t) {
    final offset = joint.channelOffset!;
    Vector3 pos = Vector3.copy(joint.offset);
    List<double> rotations = [0, 0, 0]; // X, Y, Z

    int channelIdx = 0;
    for (final channel in joint.channels) {
      final val1 = frame1[offset + channelIdx];
      final val2 = frame2[offset + channelIdx];
      final val = val1 + (val2 - val1) * t;

      switch (channel) {
        case 'Xposition':
          pos.x = val;
          break;
        case 'Yposition':
          pos.y = val;
          break;
        case 'Zposition':
          pos.z = val;
          break;
        case 'Xrotation':
          rotations[0] = val;
          break;
        case 'Yrotation':
          rotations[1] = val;
          break;
        case 'Zrotation':
          rotations[2] = val;
          break;
      }
      channelIdx++;
    }

    transform.position = pos;

    Quaternion q = Quaternion.identity();
    channelIdx = 0;
    for (final channel in joint.channels) {
      final val1 = frame1[offset + channelIdx];
      final val2 = frame2[offset + channelIdx];
      final deg = val1 + (val2 - val1) * t;
      final rad = deg * pi / 180.0;

      switch (channel) {
        case 'Xrotation':
          q *= Quaternion.axisAngle(Vector3(1, 0, 0), rad);
          break;
        case 'Yrotation':
          q *= Quaternion.axisAngle(Vector3(0, 1, 0), rad);
          break;
        case 'Zrotation':
          q *= Quaternion.axisAngle(Vector3(0, 0, 1), rad);
          break;
      }
      channelIdx++;
    }
    transform.rotation = q;
  }
}
