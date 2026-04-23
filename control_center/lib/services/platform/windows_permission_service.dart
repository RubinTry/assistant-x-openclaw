import 'package:flutter/services.dart';
import '../base/permission_service_base.dart';

class WindowsPermissionService implements PermissionServiceBase {
  static const _channel = MethodChannel('com.assistant/permission');

  @override
  Future<bool> requestMicrophonePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestMicrophonePermission');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to request microphone permission: ${e.message}');
      return false;
    }
  }

  @override
  Future<String> checkMicrophonePermission() async {
    try {
      final result = await _channel.invokeMethod<String>('checkMicrophonePermission');
      return result ?? 'unknown';
    } on PlatformException catch (e) {
      print('Failed to check microphone permission: ${e.message}');
      return 'unknown';
    }
  }
}