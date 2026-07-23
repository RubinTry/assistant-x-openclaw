import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import '../gltf/gltf_parser.dart';

/// Handles skeletal animation playback and keyframe interpolation.
class M3Animator {
  final List<GltfAnimation> animations;
  final Map<int, GltfNode> nodes; // target node index to node
  final List<GltfNode>? allNodes; // optional full node list for cloned instances
  int _currentAnimationIndex = 0;
  double _currentTime = 0.0;
  bool isPlaying = false;
  bool loop = true;
  double playRate = 1.0;

  // Cross-fade support
  int? _prevAnimationIndex;
  double _prevTime = 0.0;
  double _fadeTime = 0.0;
  double _fadeDuration = 0.0;
  bool get isFading => _fadeDuration > 0 && _fadeTime < _fadeDuration;

  M3Animator(this.animations, this.nodes, {this.allNodes});

  void play(int index) {
    _currentAnimationIndex = index;
    _currentTime = 0.0;
    isPlaying = true;
    _fadeDuration = 0.0; // Reset fade
  }

  /// Smoothly transition to another animation over the specified duration.
  void crossFade(int index, double duration) {
    if (index == _currentAnimationIndex && !isFading) return;
    if (duration <= 0) {
      play(index);
      return;
    }

    _prevAnimationIndex = _currentAnimationIndex;
    _prevTime = _currentTime;
    _currentAnimationIndex = index;
    _currentTime = 0.0;

    _fadeTime = 0.0;
    _fadeDuration = duration;
    isPlaying = true;
  }

  void update(double deltaTime) {
    if (animations.isEmpty) {
      _updateHierarchy();
      return;
    }

    if (isPlaying) {
      double blendWeight = 1.0;
      if (isFading) {
        _fadeTime += deltaTime;
        blendWeight = (_fadeTime / _fadeDuration).clamp(0.0, 1.0);
      }

      // 1. Update previous animation (if fading)
      if (isFading && _prevAnimationIndex != null) {
        _updateAnimation(_prevAnimationIndex!, _prevTime, weight: 1.0);
        final anim = animations[_prevAnimationIndex!];
        _prevTime = _advanceTime(anim, _prevTime, deltaTime);
      }

      // 2. Update current animation (with blendWeight)
      _updateAnimation(_currentAnimationIndex, _currentTime, weight: blendWeight);
      final anim = animations[_currentAnimationIndex];
      _currentTime = _advanceTime(anim, _currentTime, deltaTime);

      if (!isFading) {
        _prevAnimationIndex = null;
      }
    }

    _updateHierarchy();
  }

  double _advanceTime(GltfAnimation anim, double time, double deltaTime) {
    double newTime = time + deltaTime * playRate;

    // Get max duration
    double maxTime = 0;
    for (final sampler in anim.samplers) {
      final inputs = sampler.getInputs();
      if (inputs.isNotEmpty && inputs.last > maxTime) {
        maxTime = inputs.last;
      }
    }

    if (newTime > maxTime) {
      if (loop) {
        newTime %= maxTime;
      } else {
        newTime = maxTime;
        isPlaying = false;
      }
    }
    return newTime;
  }

  void _updateAnimation(int index, double time, {double weight = 1.0}) {
    final anim = animations[index];
    // Apply channels
    for (final channel in anim.channels) {
      if (channel.targetNodeIndex == null) continue;
      final node = nodes[channel.targetNodeIndex!];
      if (node == null) continue;

      final sampler = anim.samplers[channel.samplerIndex];
      _applySampler(node, sampler, channel.targetPath, time, weight);
    }
  }

  void _updateHierarchy() {
    if (nodes.isEmpty) return;
    final doc = nodes.values.first.document;
    final identity = Matrix4.identity();
    for (final rootIndex in doc.rootNodes) {
      final rootNode = allNodes != null ? allNodes![rootIndex] : doc.nodes[rootIndex];
      rootNode.computeWorldMatrix(identity, allNodes);
    }
  }

  void _applySampler(GltfNode node, GltfAnimationSampler sampler, String path, double time, double weight) {
    final times = sampler.getInputs();
    final values = sampler.getOutputs();

    if (times.isEmpty) return;

    // Find keyframe interval
    int prevIndex = 0;
    int nextIndex = 0;
    for (int i = 0; i < times.length - 1; i++) {
      if (time >= times[i] && time <= times[i + 1]) {
        prevIndex = i;
        nextIndex = i + 1;
        break;
      }
    }

    // If time is beyond last keyframe
    if (time >= times.last) {
      prevIndex = nextIndex = times.length - 1;
    }

    double t = 0.0;
    if (prevIndex != nextIndex) {
      t = (time - times[prevIndex]) / (times[nextIndex] - times[prevIndex]);
    }

    if (path == 'translation') {
      final v1 = _getVector3(values, prevIndex);
      final v2 = _getVector3(values, nextIndex);
      final target = Vector3(v1.x + (v2.x - v1.x) * t, v1.y + (v2.y - v1.y) * t, v1.z + (v2.z - v1.z) * t);
      if (weight >= 1.0) {
        node.translation.setFrom(target);
      } else {
        node.translation.setValues(
          node.translation.x + (target.x - node.translation.x) * weight,
          node.translation.y + (target.y - node.translation.y) * weight,
          node.translation.z + (target.z - node.translation.z) * weight,
        );
      }
    } else if (path == 'rotation') {
      final q1 = _getQuaternion(values, prevIndex);
      final q2 = _getQuaternion(values, nextIndex);
      // Manual Slerp for keyframes
      Quaternion target = _slerp(q1, q2, t);

      if (weight >= 1.0) {
        node.rotation.setFrom(target);
      } else {
        // Blend from current rotation to target
        node.rotation.setFrom(_slerp(node.rotation, target, weight));
      }
      node.rotation.normalize();
    } else if (path == 'scale') {
      final v1 = _getVector3(values, prevIndex);
      final v2 = _getVector3(values, nextIndex);
      final target = Vector3(v1.x + (v2.x - v1.x) * t, v1.y + (v2.y - v1.y) * t, v1.z + (v2.z - v1.z) * t);
      if (weight >= 1.0) {
        node.scale.setFrom(target);
      } else {
        node.scale.setValues(
          node.scale.x + (target.x - node.scale.x) * weight,
          node.scale.y + (target.y - node.scale.y) * weight,
          node.scale.z + (target.z - node.scale.z) * weight,
        );
      }
    }
  }

  Quaternion _slerp(Quaternion q1, Quaternion q2, double t) {
    double dot = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w;

    double factor2 = 1.0;
    if (dot < 0.0) {
      factor2 = -1.0;
      dot = -dot;
    }

    if (dot > 0.9995) {
      // NLerp
      return Quaternion(
        q1.x + (q2.x * factor2 - q1.x) * t,
        q1.y + (q2.y * factor2 - q1.y) * t,
        q1.z + (q2.z * factor2 - q1.z) * t,
        q1.w + (q2.w * factor2 - q1.w) * t,
      );
    } else {
      double angle = acos(dot);
      double sinTotal = sin(angle);
      double ratioA = sin((1 - t) * angle) / sinTotal;
      double ratioB = (sin(t * angle) / sinTotal) * factor2;
      return Quaternion(
        q1.x * ratioA + q2.x * ratioB,
        q1.y * ratioA + q2.y * ratioB,
        q1.z * ratioA + q2.z * ratioB,
        q1.w * ratioA + q2.w * ratioB,
      );
    }
  }

  Vector3 _getVector3(Float32List list, int index) {
    return Vector3(list[index * 3], list[index * 3 + 1], list[index * 3 + 2]);
  }

  Quaternion _getQuaternion(Float32List list, int index) {
    return Quaternion(list[index * 4], list[index * 4 + 1], list[index * 4 + 2], list[index * 4 + 3]);
  }
}
