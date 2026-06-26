import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../base/voice_assistant_service_base.dart';

class WindowsVoiceAssistantService implements VoiceAssistantServiceBase {
  Process? _pythonProcess;
  final _outputController = StreamController<String>.broadcast();
  bool _shouldKeepRunning = false;
  Timer? _monitorTimer;
  bool _processExited = false;
  bool _isStarting = false;
  Completer<void>? _startCompleter;
  bool _forceStop = false;

  @override
  Stream<String> get outputStream => _outputController.stream;
  @override
  bool get isRunning => _pythonProcess != null && !_processExited;

  String get expandedPath {
    final home = Platform.environment['USERPROFILE'] ?? 
                 Platform.environment['HOME'] ?? 
                 'C:\\Users\\${Platform.environment['USERNAME']}';
    return '$home\\.openclaw\\workspace\\voice-assistant\\assistant-x-openclaw';
  }

  String _safeDecode(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return SystemEncoding().decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      }
    }
  }

  @override
  Future<void> start() async {
    if (_isStarting && !_forceStop) {
      _addLog('正在启动中，请稍候...');
      return;
    }
    
    _isStarting = true;
    _shouldKeepRunning = true;
    _processExited = false;
    _forceStop = false;
    _startCompleter = Completer<void>();

    await _killProcessesOnPorts();

    if (!_shouldKeepRunning || _forceStop) {
      _isStarting = false;
      _processExited = true;
      _startCompleter?.complete();
      return;
    }

    _addLog('正在启动语音助手...');

    try {
      _pythonProcess = await Process.start(
        'cmd.exe',
        ['/c', 'chcp 65001 >nul && cd /d $expandedPath && scripts\\start.bat'],
        environment: {'PYTHONIOENCODING': 'utf-8'},
      );

      if (!_shouldKeepRunning || _forceStop) {
        _pythonProcess!.kill();
        _pythonProcess = null;
        _processExited = true;
        _isStarting = false;
        await _killProcessesOnPorts();
        _addLog('语音助手已停止');
        _startCompleter?.complete();
        return;
      }

      _pythonProcess!.stdout.listen((data) {
        final output = _safeDecode(data).trim();
        if (output.isNotEmpty) _addLog(output);
      });

      _pythonProcess!.stderr.listen((data) {
        final output = _safeDecode(data).trim();
        if (output.isNotEmpty) _addLog(output);
      });

      _pythonProcess!.exitCode.then((code) {
        _processExited = true;
        if (_shouldKeepRunning && !_forceStop) {
          _addLog('语音助手进程已退出 (code: $code)');
        }
      });

      _addLog('语音助手已启动 (PID: ${_pythonProcess!.pid})');
    } catch (e) {
      if (!_shouldKeepRunning || _forceStop) {
        _isStarting = false;
        _startCompleter?.complete();
        return;
      }
      _addLog('启动失败: $e');
    }

    _isStarting = false;
    if (_shouldKeepRunning && !_forceStop) {
      _startMonitoringTimer();
    }
    _startCompleter?.complete();
  }

  @override
  Future<void> stop() async {
    _forceStop = true;
    _shouldKeepRunning = false;
    _isStarting = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;

    if (_startCompleter != null && !_startCompleter!.isCompleted) {
      _startCompleter!.complete();
    }

    _addLog('正在停止语音助手...');

    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      _pythonProcess = null;
    }
    _processExited = true;

    await _killProcessesOnPorts();
    await _killJarvisOverlay();

    _addLog('语音助手已停止');
  }

  @override
  Future<void> forceCleanup() async {
    _forceStop = true;
    _shouldKeepRunning = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _processExited = true;
    _isStarting = false;

    if (_startCompleter != null && !_startCompleter!.isCompleted) {
      _startCompleter!.complete();
    }

    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      _pythonProcess = null;
    }

    await _killProcessesOnPorts();
    await _killJarvisOverlay();
  }

  Future<void> _killProcessesOnPorts() async {
    final ports = [17888, 17889, 18790];
    for (final port in ports) {
      try {
        final result = await Process.run('netstat', ['-ano'], runInShell: true);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':$port') && line.contains('LISTENING')) {
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 5) {
                final pidStr = parts.last;
                final pid = int.tryParse(pidStr);
                if (pid != null && pid > 0) {
                  _addLog('杀掉端口 $port 的进程 PID: $pid');
                  await _killProcess(pid);
                }
              }
            }
          }
        }
      } catch (e) {
        _addLog('清理端口失败: $e');
      }
    }
  }

  Future<void> _killProcess(int pid) async {
    try {
      final result = await Process.run('taskkill', ['/F', '/PID', '$pid']);
      if (result.exitCode == 0) {
        _addLog('已杀掉进程 PID: $pid');
      } else {
        _addLog('杀进程失败: ${result.stderr}');
      }
    } catch (e) {
      _addLog('杀进程异常: $e');
    }
  }

  void _startMonitoringTimer() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_shouldKeepRunning && _processExited && !_isStarting && !_forceStop) {
        _addLog('检测到语音助手已停止，正在重启...');
        start();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _killJarvisOverlay() async {
    try {
      await Process.run('taskkill', ['/F', '/IM', 'assistant_overlay.exe']);
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
  Future<bool> setDndMode(bool enabled) async {
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
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _outputController.close();
  }
}
