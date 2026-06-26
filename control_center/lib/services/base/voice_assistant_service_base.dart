abstract class VoiceAssistantServiceBase {
  Stream<String> get outputStream;
  bool get isRunning;

  Future<void> start();
  Future<void> stop();
  /// 返回是否成功通知主程序。失败（如 18790 端口未监听）时调用方应明确提示用户，
  /// 不能静默吞掉——否则勿扰没生效但用户毫无察觉，唤醒词会照常响应。
  Future<bool> setDndMode(bool enabled);
  void addLog(String message);
  void dispose();
  Future<void> forceCleanup();
}