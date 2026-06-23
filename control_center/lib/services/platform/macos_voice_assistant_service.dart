import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../base/voice_assistant_service_base.dart';

class MacOSVoiceAssistantService implements VoiceAssistantServiceBase {
  Process? _pythonProcess;
  final _outputController = StreamController<String>.broadcast();
  bool _shouldKeepRunning = false;
  Timer? _monitorTimer;
  bool _processExited = false;
  bool _isStarting = false;
  Completer<void>? _startCompleter;

  @override
  Stream<String> get outputStream => _outputController.stream;
  @override
  bool get isRunning => _pythonProcess != null && !_processExited;

  String get expandedPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.openclaw/workspace/voice-assistant/assistant-x-openclaw';
  }

  @override
  Future<void> start() async {
    if (_isStarting) return;
    _isStarting = true;
    _shouldKeepRunning = true;
    _processExited = false;
    _startCompleter = Completer<void>();

    await cleanupOldProcesses();

    if (!_shouldKeepRunning) {
      _isStarting = false;
      _startCompleter?.complete();
      return;
    }

    _addLog('正在启动语音助手...');

    try {
      _pythonProcess = await Process.start(
        '/bin/bash',
        ['-l', '-c', 'cd $expandedPath && ./scripts/start.sh'],
      );

      if (!_shouldKeepRunning) {
        _pythonProcess!.kill();
        _pythonProcess = null;
        _processExited = true;
        _isStarting = false;
        await cleanupOldProcesses();
        _addLog('语音助手已停止');
        _startCompleter?.complete();
        return;
      }

      _pythonProcess!.stdout.transform(utf8.decoder).listen((data) {
        final output = data.trim();
        if (output.isNotEmpty) _addLog(output);
      });

      _pythonProcess!.stderr.transform(utf8.decoder).listen((data) {
        final output = data.trim();
        if (output.isNotEmpty) _addLog(output);
      });

      _pythonProcess!.exitCode.then((code) {
        _processExited = true;
        if (_shouldKeepRunning) {
          _addLog('语音助手进程已退出 (code: $code)');
        }
      });

      _addLog('语音助手已启动 (PID: ${_pythonProcess!.pid})');
    } catch (e) {
      if (!_shouldKeepRunning) {
        _isStarting = false;
        _startCompleter?.complete();
        return;
      }
      _addLog('启动失败: $e');
    }

    _isStarting = false;
    if (_shouldKeepRunning) {
      _startMonitoringTimer();
    }
    _startCompleter?.complete();
  }

  @override
  Future<void> stop() async {
    _shouldKeepRunning = false;
    _isStarting = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;

    if (_startCompleter != null && !_startCompleter!.isCompleted) {
      await _startCompleter!.future;
    }

    _addLog('正在停止语音助手...');

    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      _pythonProcess = null;
    }
    _processExited = true;

    await cleanupOldProcesses();
    await _killJarvisOverlay();

    _addLog('语音助手已停止');
  }

  @override
  Future<void> forceCleanup() async {
    _shouldKeepRunning = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _processExited = true;

    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      _pythonProcess = null;
    }

    await cleanupOldProcesses();
    await _killJarvisOverlay();
  }

  Future<void> cleanupOldProcesses() async {
    final ports = [17888, 17889];
    for (final port in ports) {
      try {
        final result = await Process.run('lsof', ['-ti', ':$port']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final pids = result.stdout
              .toString()
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>();
          for (final pid in pids) {
            await _killProcess(pid);
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _killProcess(int pid) async {
    try {
      await Process.run('kill', ['-9', '$pid']);
    } catch (_) {}
  }

  void _startMonitoringTimer() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_shouldKeepRunning && _processExited && !_isStarting) {
        _addLog('检测到语音助手已停止，正在重启...');
        start();
      }
    });
  }

  Future<void> _killJarvisOverlay() async {
    try {
      await Process.run('/usr/bin/osascript', ['-e', 'tell application "jarvis_overlay" to quit']);
    } catch (_) {}
    try {
      await Process.run('/usr/bin/pkill', ['-f', 'jarvis_overlay']);
    } catch (_) {}
  }

  void _addLog(String message) {
    _outputController.add(message);
  }

  @override
  void addLog(String message) {
    _outputController.add(message);
  }

  @override
  Future<void> setDndMode(bool enabled) async {
    // Python 端 18790 是 HTTP server（do_POST 认 /dnd、/dnd/disable）。
    // 必须发真正的 HTTP POST；裸 TCP 字符串会被当成畸形请求丢弃，DND 不会生效。
    try {
      final client = HttpClient();
      final path = enabled ? '/dnd' : '/dnd/disable';
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:18790$path'))
          .timeout(const Duration(seconds: 2));
      final resp = await req.close();
      await resp.drain<void>();
      client.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _outputController.close();
  }
}