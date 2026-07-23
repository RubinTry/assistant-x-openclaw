import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'm3_video_bridge_method_channel.dart';

abstract class M3VideoBridgePlatform extends PlatformInterface {
  /// Constructs a M3VideoBridgePlatform.
  M3VideoBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static M3VideoBridgePlatform _instance = MethodChannelM3VideoBridge();

  /// The default instance of [M3VideoBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelM3VideoBridge].
  static M3VideoBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [M3VideoBridgePlatform] when
  /// they register themselves.
  static set instance(M3VideoBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
