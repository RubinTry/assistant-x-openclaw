import '../base/voice_assistant_service_base.dart';

class LinuxVoiceAssistantService implements VoiceAssistantServiceBase {
  @override
  Stream<String> get outputStream => const Stream.empty();
  @override
  bool get isRunning => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<bool> setDndMode(bool enabled) async => false;
  @override
  void addLog(String message) {}
  @override
  void dispose() {}
  @override
  Future<void> forceCleanup() async {}
}