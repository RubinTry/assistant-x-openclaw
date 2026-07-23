import 'package:vector_math/vector_math.dart';
import '../util/log.dart';
import 'bvh_data.dart';

/// A parser for Biovision Hierarchy (BVH) files.
class BvhParser {
  static BvhData parse(String content) {
    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    int lineIndex = 0;

    if (lines[lineIndex++] != 'HIERARCHY') {
      throw FormatException('BVH file must start with HIERARCHY');
    }

    final allJoints = <BvhJoint>[];
    int currentChannelOffset = 0;

    BvhJoint parseJoint() {
      final line = lines[lineIndex++];
      final parts = line.split(RegExp(r'\s+'));
      final type = parts[0]; // ROOT, JOINT, or End
      final name = (type == 'End' && parts[1] == 'Site') ? 'End Site' : parts[1];

      if (lines[lineIndex++] != '{') {
        throw FormatException('Expected { after joint definition');
      }

      // Offset
      final offsetLine = lines[lineIndex++];
      final offsetParts = offsetLine.split(RegExp(r'\s+'));
      if (offsetParts[0] != 'OFFSET') throw FormatException('Expected OFFSET');
      final offset = Vector3(double.parse(offsetParts[1]), double.parse(offsetParts[2]), double.parse(offsetParts[3]));

      final channels = <String>[];
      int? jointChannelOffset;

      if (type != 'End') {
        final channelLine = lines[lineIndex++];
        final channelParts = channelLine.split(RegExp(r'\s+'));
        if (channelParts[0] != 'CHANNELS') throw FormatException('Expected CHANNELS');
        final count = int.parse(channelParts[1]);
        for (int i = 0; i < count; i++) {
          channels.add(channelParts[2 + i]);
        }
        jointChannelOffset = currentChannelOffset;
        currentChannelOffset += count;
      }

      final children = <BvhJoint>[];
      while (lines[lineIndex] != '}') {
        children.add(parseJoint());
      }
      lineIndex++; // skip '}'

      final joint = BvhJoint(
        name: name,
        offset: offset,
        channels: channels,
        children: children,
        channelOffset: jointChannelOffset,
      );
      allJoints.add(joint);
      return joint;
    }

    final root = parseJoint();

    if (lines[lineIndex++] != 'MOTION') {
      throw FormatException('Expected MOTION section');
    }

    // Frames
    final framesLine = lines[lineIndex++];
    if (!framesLine.startsWith('Frames:')) throw FormatException('Expected Frames:');
    final frameCount = int.parse(framesLine.split(RegExp(r'\s+'))[1]);

    // Frame Time
    final frameTimeLine = lines[lineIndex++];
    if (!frameTimeLine.startsWith('Frame Time:')) throw FormatException('Expected Frame Time:');
    final frameTime = double.parse(frameTimeLine.split(RegExp(r'\s+'))[2]);

    final frames = <List<double>>[];
    for (int i = 0; i < frameCount; i++) {
      if (lineIndex >= lines.length) break;
      final motionLine = lines[lineIndex++];
      final values = motionLine.split(RegExp(r'\s+')).map(double.parse).toList();
      frames.add(values);
    }
    M3Log.i('BvhParser', 'BvhParser: Parsed ${allJoints.length} joints, $frameCount frames');

    return BvhData(root: root, frameCount: frameCount, frameTime: frameTime, allJoints: allJoints, frames: frames);
  }
}
