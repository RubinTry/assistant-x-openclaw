import '../base/permission_service_base.dart';

class LinuxPermissionService implements PermissionServiceBase {
  @override
  Future<bool> requestMicrophonePermission() async {
    return true;
  }

  @override
  Future<String> checkMicrophonePermission() async {
    return 'granted';
  }
}