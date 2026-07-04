import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/service_factory.dart';
import '../models/log_entry.dart';
import 'speaker_manage_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final _service = ServiceFactory.voiceAssistantService;
  final _permissionService = ServiceFactory.permissionService;
  final _logs = <LogEntry>[];
  // 日志上限：只保留最近 N 行，超出时丢弃最旧的，防止无限增长导致内存与重排开销膨胀
  static const int _maxLogs = 1000;
  final _scrollController = ScrollController();
  bool _isRunning = false;
  // 选中的日志行下标集合。支持：Cmd/Ctrl+A 全选、Ctrl/Cmd+左键点选、左键拖拽框选。
  // 下标随 _logs 增长/裁剪而漂移，裁剪时在 outputStream 回调里同步平移。
  final _selected = <int>{};
  // 拖拽框选的锚点行；为 null 表示当前没有进行中的拖拽。
  int? _dragAnchor;
  // 日志列表的 RenderBox key，用于把指针坐标命中到具体行下标。
  final _listKey = GlobalKey();
  ServerSocket? _tcpServer;
  static const int _speakerRejectedPort = 18792;

  // 系统通知插件：由本应用（control_center）弹出，通知图标即本应用 bundle 图标
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  bool _alreadyShow = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions();
    _service.outputStream.listen((msg) {
      setState(() {
        _logs.add(LogEntry(timestamp: DateTime.now(), message: msg));
        if (_logs.length > _maxLogs) {
          final removed = _logs.length - _maxLogs;
          _logs.removeRange(0, removed);
          // 前部裁掉 removed 行后所有下标左移；平移选中集合与拖拽锚点，丢弃被裁掉的行。
          if (_selected.isNotEmpty) {
            final shifted = _selected
                .map((i) => i - removed)
                .where((i) => i >= 0)
                .toSet();
            _selected
              ..clear()
              ..addAll(shifted);
          }
          if (_dragAnchor != null) {
            _dragAnchor = _dragAnchor! - removed;
            if (_dragAnchor! < 0) _dragAnchor = null;
          }
        }
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

  Future<void> _initNotifications() async {
    // flutter_local_notifications 仅支持 macOS/Linux，Windows 上调用会抛
    // LateInitializationError（platform instance 是 late 字段，无 Windows 实现）。
    if (!Platform.isMacOS && !Platform.isLinux) {
      debugPrint('通知初始化: 当前平台不支持系统通知，已跳过');
      return;
    }
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: false,
      );
      const settings = InitializationSettings(macOS: darwin);
      await _notifications.initialize(settings);
      final macPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      // notDetermined（从未决定）时这一步会弹系统授权框；
      // 已被用户在系统设置中关闭（denied）时，macOS 不会再弹框，request 静默返回。
      await macPlugin?.requestPermissions(
        alert: true,
        sound: true,
        badge: false,
      );
      _notificationsReady = true;
      // 每次启动都检查实际权限状态：若处于关闭态，系统不会自动弹框，
      // 改为应用内引导用户去系统设置手动开启。
      final opts = await macPlugin?.checkPermissions();
      if (mounted && opts != null && !opts.isEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNotificationDeniedDialog();
        });
      }
    } catch (e) {
      debugPrint('通知初始化失败: $e');
    }
  }

  void _showNotificationDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('通知权限未开启'),
        content: const Text(
          '语音助手的桌面通知需要系统通知权限，当前已关闭。\n'
          '请在「系统设置 › 通知 › Control Center」中允许通知。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 跳转到系统设置的「通知」面板
              Process.run('open', [
                'x-apple.systempreferences:com.apple.preference.notifications',
              ]);
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSystemNotification(
    String title,
    String text,
    bool sound,
  ) async {
    if (!_notificationsReady) return;
    try {
      final details = NotificationDetails(
        macOS: DarwinNotificationDetails(presentSound: sound),
      );
      // id 用时间戳低位，保证多条通知不互相覆盖
      final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      await _notifications.show(id, title, text, details);
    } catch (e) {
      debugPrint('弹出通知失败: $e');
    }
  }

  Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind('127.0.0.1', _speakerRejectedPort);
      _tcpServer!.listen((socket) {
        socket.listen((data) {
          // 必须按 UTF-8 解码：notify_bridge 发的 JSON 含中文，逐字节解码会乱码
          final message = utf8.decode(data, allowMalformed: true).trim();
          // 新协议：一行 JSON {"type":"notify",...} → 弹系统通知（本应用图标）
          // 旧协议：裸串 "speaker_rejected" → 弹应用内"去注册"对话框（向后兼容）
          if (message.startsWith('{')) {
            try {
              final obj = jsonDecode(message) as Map<String, dynamic>;
              if (obj['type'] == 'notify') {
                _showSystemNotification(
                  (obj['title'] ?? '').toString(),
                  (obj['text'] ?? '').toString(),
                  obj['sound'] != false,
                );
              }
            } catch (_) {}
          } else if (message == 'speaker_rejected') {
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
    if (!mounted || _alreadyShow) return;
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
    ).then((_) {
      _alreadyShow = false;
    });
    _alreadyShow = true;
  }

  void _openSpeakerManagePage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SpeakerManagePage()),
    );
  }

  Future<void> _requestPermissions() async {
    if (Platform.isMacOS || Platform.isWindows) {
      final status = await _permissionService.checkMicrophonePermission();
      if (status != 'granted') {
        await _permissionService.requestMicrophonePermission();
      }
    }
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
    setState(() => _isRunning = _service.isRunning);
  }

  void _stop() async {
    await _service.stop();
    setState(() => _isRunning = false);
  }

  void _clearConsole() {
    setState(() {
      _logs.clear();
      _selected.clear();
      _dragAnchor = null;
    });
  }

  /// 全选（Cmd/Ctrl+A）：把全部行下标塞进选中集合。
  void _selectAllLogs() {
    if (_logs.isEmpty) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(List.generate(_logs.length, (i) => i));
    });
  }

  /// 取消选中（点击空白处或 Esc）。
  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(() {
      _selected.clear();
      _dragAnchor = null;
    });
  }

  /// 复制（Cmd/Ctrl+C）：把选中的行按顺序拷进剪贴板。
  void _copySelectedLogs() {
    if (_selected.isEmpty) return;
    final indices = _selected.where((i) => i >= 0 && i < _logs.length).toList()
      ..sort();
    if (indices.isEmpty) return;
    final text = indices
        .map((i) => '[${_logs[i].formattedTimestamp}] ${_logs[i].message}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
  }

  /// 命中测试：把全局指针坐标映射到日志行下标；命中空白处返回 null。
  int? _indexAtPosition(Offset globalPos) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPos);
    final result = BoxHitTestResult();
    if (!box.hitTest(result, position: local)) return null;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final meta = target.metaData;
        if (meta is int) return meta;
      }
    }
    return null;
  }

  bool get _isMultiSelectModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _onPointerDown(PointerDownEvent e) {
    // 仅处理鼠标左键
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) {
      return;
    }
    final idx = _indexAtPosition(e.position);
    if (idx == null) {
      // 点空白：取消选中，不进入拖拽
      _clearSelection();
      return;
    }
    if (_isMultiSelectModifierPressed) {
      // Ctrl/Cmd+左键：切换单行，不启动拖拽框选
      setState(() {
        if (!_selected.add(idx)) _selected.remove(idx);
      });
      _dragAnchor = null;
    } else {
      // 普通左键按下：起一个新的框选，锚定当前行
      setState(() {
        _selected
          ..clear()
          ..add(idx);
      });
      _dragAnchor = idx;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_dragAnchor == null) return;
    final idx = _indexAtPosition(e.position);
    if (idx == null) return;
    final lo = min(_dragAnchor!, idx);
    final hi = max(_dragAnchor!, idx);
    setState(() {
      _selected
        ..clear()
        ..addAll(List.generate(hi - lo + 1, (i) => lo + i));
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    _dragAnchor = null;
  }

  void handleTrayAction(String action) {
    switch (action) {
      case 'start':
        _start();
        break;
      case 'stop':
        _forceStop();
        break;
    }
  }

  Future<void> _forceStop() async {
    if (Platform.isMacOS) {
      final service = _service as dynamic;
      await service.forceCleanup();
    } else if (Platform.isWindows) {
      final service = _service as dynamic;
      await service.forceCleanup();
    } else {
      _service.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR):
            StartIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            StopIntent(),
        // 全选 / 复制 / 取消选中：macOS 用 Cmd，Windows/Linux 用 Ctrl
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA):
            SelectAllLogsIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
            SelectAllLogsIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC):
            CopyLogsIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
            CopyLogsIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): ClearSelectionIntent(),
      },
      child: Actions(
        actions: {
          StartIntent: CallbackAction<StartIntent>(
            onInvoke: (_) {
              if (!_isRunning) _start();
              return null;
            },
          ),
          StopIntent: CallbackAction<StopIntent>(
            onInvoke: (_) {
              if (_isRunning) _stop();
              return null;
            },
          ),
          SelectAllLogsIntent: CallbackAction<SelectAllLogsIntent>(
            onInvoke: (_) {
              _selectAllLogs();
              return null;
            },
          ),
          CopyLogsIntent: CallbackAction<CopyLogsIntent>(
            onInvoke: (_) {
              _copySelectedLogs();
              return null;
            },
          ),
          ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(
            onInvoke: (_) {
              _clearSelection();
              return null;
            },
          ),
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
              Icon(
                Icons.mic,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
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
                width: 8,
                height: 8,
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SpeakerManagePage(
                    onLog: (msg) {
                      _service.addLog(msg);
                    },
                  ),
                ),
              );
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
                : Listener(
                    // Ctrl/Cmd+左键点选、左键拖拽框选，都在这里统一接管指针事件
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    child: ScrollbarTheme(
                      // 深色背景下默认滚动条几乎不可见，这里显式给出可见的粗细/颜色/常驻轨道
                      data: ScrollbarThemeData(
                        thumbVisibility: WidgetStateProperty.all(true),
                        trackVisibility: WidgetStateProperty.all(true),
                        thickness: WidgetStateProperty.all(8),
                        radius: const Radius.circular(4),
                        thumbColor: WidgetStateProperty.all(
                          const Color(0xFF6B6B6B),
                        ),
                        trackColor: WidgetStateProperty.all(
                          const Color(0xFF2A2A2A),
                        ),
                        trackBorderColor: WidgetStateProperty.all(
                          Colors.transparent,
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: ListView.builder(
                          key: _listKey,
                          controller: _scrollController,
                          // 右侧留出滚动条宽度，避免轨道压住日志文本或被圆角边框裁掉
                          padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            // MetaData 携带行下标，供 _indexAtPosition 命中测试识别行
                            return MetaData(
                              metaData: index,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                color: _selected.contains(index)
                                    ? const Color(0x553B82F6)
                                    : null,
                                child: Text(
                                  '[${log.formattedTimestamp}] ${log.message}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0xFFE0E0E0),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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

class SelectAllLogsIntent extends Intent {}

class CopyLogsIntent extends Intent {}

class ClearSelectionIntent extends Intent {}
