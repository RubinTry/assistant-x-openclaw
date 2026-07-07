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
import '../theme.dart';
import 'global_config_page.dart';
import 'speaker_manage_page.dart';
import 'model_manage_page.dart';

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
          // 新协议：
          //   {"type":"notify",...} → 弹系统通知（本应用图标）
          //   {"type":"wake_rejected",...} → 弹应用内拒绝原因对话框
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
              } else if (obj['type'] == 'wake_rejected') {
                _showWakeRejectedDialog(
                  title: (obj['title'] ?? '唤醒被拒绝').toString(),
                  message: (obj['message'] ?? '本次唤醒未通过验证。').toString(),
                  action: (obj['action'] ?? 'none').toString(),
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
    _showWakeRejectedDialog(
      title: '声纹验证失败',
      message: '未检测到已注册的声纹样本，请先注册声纹。',
      action: 'speaker',
    );
  }

  void _showWakeRejectedDialog({
    required String title,
    required String message,
    String action = 'none',
  }) {
    if (!mounted || _alreadyShow) return;
    final showSpeakerAction = action == 'speaker';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(showSpeakerAction ? '取消' : '知道了'),
          ),
          if (showSpeakerAction)
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
      MaterialPageRoute(
        builder: (_) => const HudRoute(child: SpeakerManagePage()),
      ),
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
                _buildTopBar(),
                Expanded(child: _buildLogConsole()),
                _buildMetricDock(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶栏：左侧品牌 + 运行状态胶囊；右侧启动/停止 + 管理页入口。
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const ReactorMark(size: 88, icon: Icons.mic),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Flexible(
                          child: Text(
                            '语音助手控制中心',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusPill(active: _isRunning, compact: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Voice runtime, identity gate, and fast-path model routing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              if (!_isRunning)
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF021018),
                    minimumSize: const Size(150, 54),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger.withValues(alpha: 0.16),
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(150, 54),
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              _topNavButton(
                icon: Icons.person_outline,
                label: '声纹',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HudRoute(
                        child: SpeakerManagePage(
                          onLog: (msg) {
                            _service.addLog(msg);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              _topNavButton(
                icon: Icons.memory_outlined,
                label: '模型',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HudRoute(child: ModelManagePage()),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              _topNavButton(
                icon: Icons.tune,
                label: '配置',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HudRoute(child: GlobalConfigPage()),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _hudStatusCard(
                  icon: Icons.monitor_heart_outlined,
                  title: '核心状态',
                  body: _isRunning ? '助手在线，正在监听唤醒链路' : '待机中，点击启动接管语音链路',
                  footerLabel: '系统状态',
                  footerValue: _isRunning ? '正常' : '待机',
                  color: AppColors.success,
                  visual: const _SignalWave(color: AppColors.success),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _hudStatusCard(
                  icon: Icons.terminal,
                  title: '控制台',
                  body: '${_logs.length} 行输出，支持拖拽选择与复制',
                  footerLabel: '输出模式',
                  footerValue: '实时',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _hudStatusCard(
                  icon: Icons.bolt,
                  title: '快路径',
                  body: '轻消息直答，重任务升级主脑',
                  footerLabel: '路由状态',
                  footerValue: '快路径',
                  color: AppColors.warning,
                  visual: const _OrbitDisplay(color: AppColors.warning),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topNavButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(116, 54),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
    );
  }

  Widget _hudStatusCard({
    required IconData icon,
    required String title,
    required String body,
    required String footerLabel,
    required String footerValue,
    required Color color,
    Widget? visual,
  }) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.10),
            AppColors.surfaceGlass,
            Colors.black.withValues(alpha: 0.16),
          ],
        ),
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (visual != null)
            Positioned(right: 0, top: 6, bottom: 6, child: visual),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.38)),
                    ),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: color.withValues(alpha: 0.14)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$footerLabel：',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      footerValue,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDock() {
    final wakeCount = _logs
        .where(
          (log) =>
              log.message.contains('检测到唤醒词') || log.message.contains('wake'),
        )
        .length;
    final speakerPass = _logs.any(
      (log) => log.message.contains('声纹') && log.message.contains('验证通过'),
    );
    final fastHits = _logs.where((log) => log.message.contains('快路径')).length;
    final brainCalls = _logs
        .where(
          (log) =>
              log.message.contains('OpenClaw') ||
              log.message.contains('Hermes'),
        )
        .length;
    final load = (_logs.length % 37) + 12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
      child: Row(
        children: [
          Expanded(
            child: _metricCard(
              Icons.schedule,
              '运行时长',
              _isRunning ? '在线' : '待机',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(Icons.graphic_eq, '唤醒事件', '$wakeCount 次'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              Icons.verified_user_outlined,
              '声纹验证',
              speakerPass ? '通过' : '待验证',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: _metricCard(Icons.bolt, '快路径命中', '$fastHits 次')),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              Icons.psychology_outlined,
              '主脑调用',
              '$brainCalls 次',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              Icons.show_chart,
              '系统负载',
              '$load%',
              trailing: const _MetricSparkline(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    IconData icon,
    String label,
    String value, {
    Widget? trailing,
  }) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppGradients.panel,
        borderRadius: AppShape.borderRadius,
        border: Border.all(
          color: AppColors.borderBright.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(icon, size: 19, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// 控制台头部的轻量操作按钮（图标 + 文案）。
  Widget _consoleAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogConsole() {
    return Panel(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppShape.radius),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text(
                  '运行控制台',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_logs.length} 行',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                _consoleAction(Icons.clear_all, '清空', _clearConsole),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      '等待语音助手输出',
                      style: TextStyle(color: AppColors.textMuted),
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
                          AppColors.borderBright,
                        ),
                        trackColor: WidgetStateProperty.all(
                          AppColors.surfaceHigh,
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
                                    ? AppColors.consoleSelection
                                    : null,
                                child: Text(
                                  '[${log.formattedTimestamp}] ${log.message}',
                                  style: AppTextStyles.consoleLed,
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

class _SignalWave extends StatelessWidget {
  final Color color;
  const _SignalWave({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      height: 72,
      child: CustomPaint(painter: _SignalWavePainter(color)),
    );
  }
}

class _SignalWavePainter extends CustomPainter {
  final Color color;
  const _SignalWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final path = Path();
    final points = <double>[
      0.48,
      0.44,
      0.55,
      0.36,
      0.68,
      0.24,
      0.78,
      0.31,
      0.50,
      0.72,
      0.22,
      0.66,
      0.44,
      0.20,
      0.70,
      0.36,
      0.55,
      0.62,
      0.42,
    ];
    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / (points.length - 1);
      final y = points[i] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      Paint()
        ..color = color.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrbitDisplay extends StatelessWidget {
  final Color color;
  const _OrbitDisplay({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: CustomPaint(painter: _OrbitPainter(color)),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Color color;
  const _OrbitPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in <double>[18, 34, 50]) {
      canvas.drawCircle(center, radius, stroke);
    }
    final axis = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, 8),
      Offset(center.dx, size.height - 8),
      axis,
    );
    canvas.drawLine(
      Offset(8, center.dy),
      Offset(size.width - 8, center.dy),
      axis,
    );

    final dot = Paint()..color = color;
    canvas.drawCircle(center, 5, dot);
    for (final point in <Offset>[
      Offset(center.dx, center.dy - 50),
      Offset(center.dx + 50, center.dy),
      Offset(center.dx - 34, center.dy),
      Offset(center.dx, center.dy + 34),
    ]) {
      canvas.drawCircle(point, 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricSparkline extends StatelessWidget {
  const _MetricSparkline();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 54,
      height: 28,
      child: CustomPaint(painter: _MetricSparkPainter()),
    );
  }
}

class _MetricSparkPainter extends CustomPainter {
  const _MetricSparkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path();
    final values = <double>[
      0.82,
      0.76,
      0.78,
      0.58,
      0.62,
      0.34,
      0.42,
      0.18,
      0.28,
    ];
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = values[i] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StartIntent extends Intent {}

class StopIntent extends Intent {}

class SelectAllLogsIntent extends Intent {}

class CopyLogsIntent extends Intent {}

class ClearSelectionIntent extends Intent {}
