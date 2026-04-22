import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../services/voice_assistant_service.dart';
import '../models/log_entry.dart';
import 'speaker_manage_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final _service = VoiceAssistantService();
  final _logs = <LogEntry>[];
  final _scrollController = ScrollController();
  bool _isRunning = false;
  bool _isWindowVisible = true;
  ServerSocket? _tcpServer;
  static const int _speakerRejectedPort = 18792;

  @override
  void initState() {
    super.initState();
    _service.outputStream.listen((msg) {
      setState(() {
        _logs.add(LogEntry(timestamp: DateTime.now(), message: msg));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
    _startTcpServer();
  }

  Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind('127.0.0.1', _speakerRejectedPort);
      _tcpServer!.listen((socket) {
        socket.listen((data) {
          final message = String.fromCharCodes(data).trim();
          if (message == 'speaker_rejected') {
            _showSpeakerRejectedDialog();
          }
          socket.add('ok\n'.codeUnits);
          socket.close();
        });
      });
    } catch (e) {
      debugPrint('TCP server error: $e');
    }
  }

  void _showSpeakerRejectedDialog() {
    debugPrint('[_showSpeakerRejectedDialog] START mounted=$mounted _isWindowVisible=$_isWindowVisible');
    if (!mounted || !_isWindowVisible) {
      debugPrint('[_showSpeakerRejectedDialog] skipped: mounted=$mounted _isWindowVisible=$_isWindowVisible');
      return;
    }
    debugPrint('[_showSpeakerRejectedDialog] showing dialog');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('声纹验证失败'),
        content: const Text('未检测到已注册的声纹样本，请先注册声纹。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openSpeakerManagePage();
            },
            child: const Text('去注册'),
          ),
        ],
      ),
    );
  }

  void _openSpeakerManagePage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SpeakerManagePage()),
    );
  }

  @override
  void dispose() {
    _tcpServer?.close();
    _service.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _start() async {
    await _service.start();
    setState(() => _isRunning = true);
  }

  void _stop() async {
    await _service.stop();
    setState(() => _isRunning = false);
  }

  void _clearConsole() {
    setState(() => _logs.clear());
  }

  void handleTrayAction(String action) {
    switch (action) {
      case 'start':
        if (!_isRunning) _start();
        break;
      case 'stop':
        if (_isRunning) _stop();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR): StartIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): StopIntent(),
      },
      child: Actions(
        actions: {
          StartIntent: CallbackAction<StartIntent>(onInvoke: (_) { if (!_isRunning) _start(); return null; }),
          StopIntent: CallbackAction<StopIntent>(onInvoke: (_) { if (_isRunning) _stop(); return null; }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                _buildHeader(),
                _buildControls(),
                Expanded(child: _buildLogConsole()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '语音助手控制中心',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRunning ? const Color(0xFF4CAF50) : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isRunning ? '运行中' : '已停止',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: _isRunning ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _isRunning ? _stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _clearConsole,
            icon: const Icon(Icons.clear_all),
            label: const Text('清空控制台'),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SpeakerManagePage(onLog: (msg) {
                _service.addLog(msg);
              })));
            },
            icon: const Icon(Icons.person),
            label: const Text('声纹管理'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogConsole() {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '控制台输出',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志输出',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _logs.map((log) => '[${log.formattedTimestamp}] ${log.message}').join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFE0E0E0),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class StartIntent extends Intent {}
class StopIntent extends Intent {}