abstract class VoiceAssistantServiceBase {
  Stream<String> get outputStream;
  bool get isRunning;

  Future<void> start();
  Future<void> stop();
  Future<void> setDndMode(bool enabled);
  void addLog(String message);
  void dispose();
  Future<void> forceCleanup();
}