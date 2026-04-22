abstract class PermissionServiceBase {
  Future<bool> requestMicrophonePermission();
  Future<String> checkMicrophonePermission();
}