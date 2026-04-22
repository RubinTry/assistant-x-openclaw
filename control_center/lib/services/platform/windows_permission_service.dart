import '../base/permission_service_base.dart';

class WindowsPermissionService implements PermissionServiceBase {
  @override
  Future<bool> requestMicrophonePermission() async {
    return false;
  }

  @override
  Future<String> checkMicrophonePermission() async {
    return 'unknown';
  }
}