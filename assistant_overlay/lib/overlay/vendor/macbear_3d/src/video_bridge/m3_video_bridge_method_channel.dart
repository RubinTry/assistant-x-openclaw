import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'm3_video_bridge_platform_interface.dart';

/// An implementation of [M3VideoBridgePlatform] that uses method channels.
class MethodChannelM3VideoBridge extends M3VideoBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('m3_video_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
