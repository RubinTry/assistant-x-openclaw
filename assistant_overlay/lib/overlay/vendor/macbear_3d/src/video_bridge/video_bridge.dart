import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class M3VideoBridge {
  static const MethodChannel _channel = MethodChannel('com.macbear.angle_test/video');

  static Future<bool> registerSurface({required int textureId, required String assetPath}) async {
    debugPrint("*** registerSurface $textureId $assetPath");
    final bool? result = await _channel.invokeMethod('registerSurface', {
      'textureId': textureId,
      'assetPath': assetPath,
    });
    return result ?? false;
  }

  static Future<dynamic> updateSurface({required int textureId}) async {
    return await _channel.invokeMethod('updateSurface', {'textureId': textureId});
  }

  static Future<void> release({required int textureId}) async {
    await _channel.invokeMethod('release', {'textureId': textureId});
  }

  static Future<void> play({required int textureId}) async {
    await _channel.invokeMethod('play', {'textureId': textureId});
  }

  static Future<void> pause({required int textureId}) async {
    await _channel.invokeMethod('pause', {'textureId': textureId});
  }

  static Future<void> seekTo({required int textureId, required double seconds}) async {
    await _channel.invokeMethod('seekTo', {'textureId': textureId, 'seconds': seconds});
  }

  static Future<double> getDuration({required int textureId}) async {
    final double? result = await _channel.invokeMethod('getDuration', {'textureId': textureId});
    return result ?? 0.0;
  }

  static Future<double> getPosition({required int textureId}) async {
    final double? result = await _channel.invokeMethod('getPosition', {'textureId': textureId});
    return result ?? 0.0;
  }
}

/// Stub class for Web plugin registration.
class M3VideoBridgePlugin {
  static void registerWith(dynamic registrar) {
    // No-op for web, as video bridge is handled via HtmlElementView or WebGL textures.
  }
}
