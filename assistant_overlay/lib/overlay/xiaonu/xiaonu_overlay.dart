import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/agent_visual.dart';

/// 小奴特效 —— 一只会动的猫（GIF 状态机）
///
/// 素材来源：codex-pets.net（pifei），每个状态一张 GIF，放在 assets/xiaonu/ 下。
/// 实现思路：
///   - 猫本体在 buildEffects 中用 Image.asset 播放 GIF，按命令切换当前 GIF；
///   - GIF 自带循环，无需逐帧控制；
///   - 状态切换通过 ValueNotifier 驱动局部重建（支持 Timer 延时回到 idle）；
///   - 显隐/缩放复用 AnimationController，与 jarvis / 林妹妹保持一致。
///
/// 注意：name 必须为 'xiao-nu'，与后端 assistants.json 的 visual 字段对应。
class Xiaonupet implements AgentVisual {
  final TickerProvider vsync;

  Xiaonupet({required this.vsync}) {
    _userScrollController = ScrollController();
    _aiScrollController = ScrollController();
    _initAnimationControllers();
  }

  // ----------------------------------------------------------------------
  // 状态定义
  // ----------------------------------------------------------------------

  /// 各状态对应的 GIF 资源路径
  static const Map<String, String> _stateAssets = {
    'idle': 'assets/xiaonu/idle.gif',
    'waving': 'assets/xiaonu/waving.gif',
    'waiting': 'assets/xiaonu/waiting.gif',
    'running': 'assets/xiaonu/running.gif',
    'run_left': 'assets/xiaonu/run_left.gif',
    'run_right': 'assets/xiaonu/run_right.gif',
    'jumping': 'assets/xiaonu/jumping.gif',
    'failed': 'assets/xiaonu/failed.gif',
    'review': 'assets/xiaonu/review.gif',
  };

  /// 当前猫的状态（驱动 GIF 切换）
  final ValueNotifier<String> _state = ValueNotifier<String>('idle');

  /// 实时音量（0.0~1.0），用于讲话时的微缩放脉冲（不切换 GIF）。
  /// 注：后端 audio_level 命令目前尚未接线，接上即生效。
  final ValueNotifier<double> _audioLevel = ValueNotifier<double>(0.0);

  /// 终端文本
  final List<String> _userMessages = [];
  final List<String> _aiMessages = [];
  String _currentUserText = '';
  String _currentAiText = '';

  late ScrollController _userScrollController;
  late ScrollController _aiScrollController;

  // 显隐 / 缩放 / 终端滑入
  late AnimationController _opacityController;
  late AnimationController _scaleController;
  late AnimationController _leftTerminalSlideController;
  late AnimationController _rightTerminalSlideController;

  // 主题色（贴合黑白猫：暖奶白底 + 炭灰描边）
  static const Color _themeColor = Color(0xFF3A3A3A);
  static const Color _terminalBackground = Color(0xFFFFF6E9);

  void _initAnimationControllers() {
    _opacityController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
    _scaleController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
      lowerBound: 0.0,
      upperBound: 2.0,
    );
    _leftTerminalSlideController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
    );
    _rightTerminalSlideController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
    );
  }

  @override
  String get name => 'xiao-nu';

  /// 循环播放的持续态（一直循环，直到命令切走）
  static const Set<String> _loopStates = {
    'idle',
    'waiting',
    'running',
    'review',
  };

  /// 一次性动作播完后自动转向的状态。
  /// 未列出的一次性动作（如 run_left 退场）播完停在末帧。
  static const Map<String, String> _afterOnce = {
    'run_right': 'waving', // 入场：跑入 → 招手
    'waving': 'idle', // 招完手 → 待机
    'jumping': 'idle', // 庆祝 → 待机
    'failed': 'idle', // 沮丧 → 待机
  };

  static bool _isLoop(String state) => _loopStates.contains(state);

  /// 切换猫的状态
  void _setState(String state) {
    if (!_stateAssets.containsKey(state)) return;
    _state.value = state;
  }

  // ----------------------------------------------------------------------
  // 命令处理
  //
  // 后端实际发送的命令（src/assistants/custom_visual.py）：
  //   wake / hide / reset_scale
  //   user:{text} / user:(空清屏) / ai:{text} / ai:(空清屏)
  //   tool_call:{name}:{args} / tool_call_end:   （目前未接线）
  //   audio_level:{0.0~1.0}                       （目前未接线）
  //   agent:{id} 由 AgentOverlay 调度器处理，不在此。
  // ----------------------------------------------------------------------

  @override
  void handleCommand(String command) {
    if (command == 'wake') {
      _opacityController.forward();
      _scaleController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
      // 入场：跑入 → 招手 → 待机，链条由帧播放完成自动驱动（见 _afterOnce）
      _setState('run_right');
    } else if (command == 'reset_scale') {
      // 用户说完，缩放复位；AI 即将回复 —— 进入思考态
      if (_scaleController.value > 1.0) {
        _scaleController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      _setState('review');
    } else if (command == 'hide') {
      // 退场序列：跑出 → 淡出缩小
      _setState('run_left');
      _opacityController.reverse();
      _scaleController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInCubic,
      );
      _leftTerminalSlideController.reverse();
      _rightTerminalSlideController.reverse();
      _audioLevel.value = 0.0;
      _userMessages.clear();
      _aiMessages.clear();
      _currentUserText = '';
      _currentAiText = '';
      // 下次 wake 会从 run_right 重新开始，无需额外复位。
    } else if (command.startsWith('audio_level:')) {
      // 实时音量 —— 仅驱动微缩放脉冲，不切换 GIF
      final raw = command.substring('audio_level:'.length).trim();
      final level = double.tryParse(raw) ?? 0.0;
      _audioLevel.value = level.clamp(0.0, 1.0).toDouble();
    } else if (command.startsWith('tool_call_end:')) {
      // 工具结束 / 随清屏发送 —— 不改姿态
      return;
    } else if (command.startsWith('tool_call:')) {
      // 调用工具 —— 审阅/思考态
      _setState('review');
    } else if (command.startsWith('effect:')) {
      // 扩展位：后端暂不发送，留作手动/未来触发 jumping / failed
      final effect = command.substring('effect:'.length).trim();
      switch (effect) {
        case 'success':
          _setState('jumping');
          break;
        case 'error':
          _setState('failed');
          break;
        case 'idle':
          _setState('idle');
          break;
        default:
          break;
      }
    } else if (command.startsWith('user:')) {
      final text = command.substring(5);
      if (text.isEmpty) return; // 空串=清屏，忽略
      // 用户说话 —— 歪头聆听
      _setState('waiting');
      if (_currentUserText.isNotEmpty && text.startsWith(_currentUserText)) {
        _currentUserText = text;
      } else {
        if (_currentUserText.isNotEmpty) {
          _userMessages.add(_currentUserText);
        }
        _currentUserText = text;
        if (_rightTerminalSlideController.value == 0) {
          _rightTerminalSlideController.forward();
        }
      }
      _scrollToBottom(_userScrollController);
    } else if (command.startsWith('ai:')) {
      final text = command.substring(3);
      if (text.isEmpty) return; // 空串=清屏，忽略
      // AI 回复 —— 活跃讲话
      _setState('running');
      if (_currentAiText.isNotEmpty && text.startsWith(_currentAiText)) {
        _currentAiText = text;
      } else {
        if (_currentAiText.isNotEmpty) {
          _aiMessages.add(_currentAiText);
        }
        _currentAiText = text;
        if (_leftTerminalSlideController.value == 0) {
          _leftTerminalSlideController.forward();
        }
      }
      _scrollToBottom(_aiScrollController);
    }
  }

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  // ----------------------------------------------------------------------
  // 特效区 —— 猫本体
  // ----------------------------------------------------------------------

  @override
  Widget buildEffects(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    const catSize = 260.0;

    return Center(
      child: SizedBox(
        width: catSize,
        height: catSize,
        child: AnimatedBuilder(
          animation: _opacityController,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityController.value,
              child: AnimatedBuilder(
                // 缩放同时受显隐缩放控制器与实时音量驱动
                animation: Listenable.merge([_scaleController, _audioLevel]),
                builder: (context, child) {
                  // 音量越大，叠加越明显的微脉冲（最多 +6%）
                  final pulse = 1.0 + _audioLevel.value * 0.06;
                  return Transform.scale(
                    scale: _scaleController.value * pulse,
                    child: child,
                  );
                },
                child: _GifPlayer(
                  state: _state,
                  assets: _stateAssets,
                  isLoop: _isLoop,
                  afterOnce: _afterOnce,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 终端区
  // ----------------------------------------------------------------------

  @override
  Widget buildAiTerminal(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final double terminalHeight = screenHeight / 3;
    final leftSlide =
        Tween<Offset>(begin: const Offset(-1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _leftTerminalSlideController,
            curve: Curves.easeOutCubic,
          ),
        );

    return SlideTransition(
      position: leftSlide,
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: EdgeInsets.only(left: 40, top: screenHeight * 0.25),
          child: SizedBox(
            height: terminalHeight,
            child: _buildTerminal(
              messages: _aiMessages,
              currentText: _currentAiText,
              maxHeight: terminalHeight,
              scrollController: _aiScrollController,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildUserTerminal(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final double terminalHeight = screenHeight / 3;
    final rightSlide =
        Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _rightTerminalSlideController,
            curve: Curves.easeOutCubic,
          ),
        );

    return SlideTransition(
      position: rightSlide,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: EdgeInsets.only(right: 40, bottom: screenHeight * 0.25),
          child: SizedBox(
            height: terminalHeight,
            child: _buildTerminal(
              messages: _userMessages,
              currentText: _currentUserText,
              maxHeight: terminalHeight,
              scrollController: _userScrollController,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminal({
    required List<String> messages,
    required String currentText,
    required double maxHeight,
    required ScrollController scrollController,
  }) {
    final List<Widget> items = [];
    for (int i = 0; i < messages.length; i++) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            messages[i],
            style: const TextStyle(color: Colors.black54, fontSize: 14),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (items.isNotEmpty) {
      items.add(const Divider(color: Colors.black12, height: 16));
    }
    if (currentText.isNotEmpty) {
      items.add(
        Text(
          currentText,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else if (items.isEmpty) {
      items.add(
        const Text(
          '...',
          style: TextStyle(
            color: Colors.black38,
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Container(
      width: 350,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: _terminalBackground.withAlpha(220),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _themeColor.withAlpha(40), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: ListView(
        controller: scrollController,
        shrinkWrap: true,
        children: items,
      ),
    );
  }

  @override
  Widget buildToolCallTerminal(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _state.dispose();
    _audioLevel.dispose();
    _userScrollController.dispose();
    _aiScrollController.dispose();
    _opacityController.dispose();
    _scaleController.dispose();
    _leftTerminalSlideController.dispose();
    _rightTerminalSlideController.dispose();
  }
}

// =====================================================================
// 逐帧 GIF 播放器
//
// 用 dart:ui 自行解码 GIF 帧并按每帧真实时长播放，从而精确控制：
//   - 循环态（idle/waiting/running/review）：无限循环；
//   - 一次性态（waving/jumping/failed/run_right/run_left）：播一遍即停，
//     并按 afterOnce 自动转向下一状态（未配置者停在末帧）。
// 这样瞬时动作不会像 Image.asset 那样无脑重复，显得更自然。
// =====================================================================

class _GifFrame {
  final ui.Image image;
  final Duration duration;
  const _GifFrame(this.image, this.duration);
}

class _GifPlayer extends StatefulWidget {
  /// 共享的状态源（与 Xiaonupet 同一个，便于回写推进 afterOnce）
  final ValueNotifier<String> state;
  final Map<String, String> assets;
  final bool Function(String) isLoop;
  final Map<String, String> afterOnce;

  const _GifPlayer({
    required this.state,
    required this.assets,
    required this.isLoop,
    required this.afterOnce,
  });

  @override
  State<_GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends State<_GifPlayer> {
  final Map<String, List<_GifFrame>> _cache = {};
  List<_GifFrame>? _frames;
  int _frameIndex = 0;
  Timer? _frameTimer;
  String _currentState = '';
  int _playToken = 0; // 防止异步加载竞态
  bool _error = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _switchTo(widget.state.value);
  }

  @override
  void didUpdateWidget(covariant _GifPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _switchTo(widget.state.value);
    }
  }

  void _onStateChanged() => _switchTo(widget.state.value);

  Future<void> _switchTo(String state) async {
    // 已在播放同一状态：保持当前循环/播放，避免每个流式 token 都重启 GIF
    if (state == _currentState && _frames != null) return;
    _currentState = state;
    _frameTimer?.cancel();
    final token = ++_playToken;

    final asset = widget.assets[state];
    if (asset == null) {
      _setError();
      return;
    }

    var frames = _cache[asset];
    if (frames == null) {
      try {
        frames = await _loadGif(asset);
        _cache[asset] = frames;
      } catch (_) {
        if (token == _playToken) _setError();
        return;
      }
    }
    if (token != _playToken || !mounted) return; // 加载期间状态又变了
    setState(() {
      _error = false;
      _frames = frames;
      _frameIndex = 0;
    });
    _scheduleFrame(token);
  }

  void _setError() {
    if (!mounted) return;
    setState(() {
      _error = true;
      _frames = null;
    });
  }

  void _scheduleFrame(int token) {
    final frames = _frames;
    if (frames == null || frames.isEmpty) return;
    var dur = frames[_frameIndex].duration;
    if (dur.inMilliseconds <= 0) dur = const Duration(milliseconds: 100);
    _frameTimer = Timer(dur, () {
      if (token != _playToken || !mounted) return;
      _advance(token);
    });
  }

  void _advance(int token) {
    final frames = _frames;
    if (frames == null) return;
    final next = _frameIndex + 1;
    if (next < frames.length) {
      setState(() => _frameIndex = next);
      _scheduleFrame(token);
    } else if (widget.isLoop(_currentState)) {
      // 循环态：回到第 0 帧继续
      setState(() => _frameIndex = 0);
      _scheduleFrame(token);
    } else {
      // 一次性态：停在末帧；若配置了后继状态则自动转向
      final nextState = widget.afterOnce[_currentState];
      if (nextState != null && nextState != _currentState) {
        widget.state.value = nextState; // 触发 listener → _switchTo
      }
    }
  }

  Future<List<_GifFrame>> _loadGif(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frames = <_GifFrame>[];
    for (int i = 0; i < codec.frameCount; i++) {
      final info = await codec.getNextFrame();
      frames.add(_GifFrame(info.image, info.duration));
    }
    codec.dispose();
    return frames;
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _frameTimer?.cancel();
    for (final list in _cache.values) {
      for (final f in list) {
        f.image.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Text('🐱', style: TextStyle(fontSize: 80)),
      );
    }
    final frames = _frames;
    if (frames == null || frames.isEmpty) {
      return const SizedBox.expand();
    }
    return RawImage(
      image: frames[_frameIndex].image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
