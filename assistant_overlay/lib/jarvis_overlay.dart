import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'agent_visual.dart';

class _JarvisShaderPainter extends CustomPainter {
  final FragmentProgram program;
  final double outerRingRotation;
  final double arcsRotation;
  final double dataRingRotation;
  final double innerRingRotation;
  final double pulseValue;
  final double speakingScale;
  final double effectState;

  _JarvisShaderPainter({
    required this.program,
    required this.outerRingRotation,
    required this.arcsRotation,
    required this.dataRingRotation,
    required this.innerRingRotation,
    required this.pulseValue,
    required this.speakingScale,
    required this.effectState,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;

    final shader = program.fragmentShader();
    shader.setFloat(0, outerRingRotation);
    shader.setFloat(1, canvasSize.width);
    shader.setFloat(2, canvasSize.height);
    shader.setFloat(3, arcsRotation);
    shader.setFloat(4, dataRingRotation);
    shader.setFloat(5, innerRingRotation);
    shader.setFloat(6, pulseValue);
    shader.setFloat(7, speakingScale);
    shader.setFloat(8, effectState);

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.srcOver;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_JarvisShaderPainter oldDelegate) {
    return true;
  }
}

class _JarvisTextPainter extends CustomPainter {
  final String currentEffect;

  _JarvisTextPainter({required this.currentEffect});

  Color get primaryColor {
    switch (currentEffect) {
      case 'success':
        return const Color(0xFF2A9999);
      case 'error':
        return const Color(0xFFFF4444);
      default:
        return const Color(0xFF3A9F9F);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final textPainter = TextPainter(
      text: TextSpan(
        text: "J.A.R.V.I.S.",
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          shadows: [
            Shadow(color: primaryColor, blurRadius: 10),
            Shadow(color: primaryColor.withAlpha(150), blurRadius: 20),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(minWidth: 0, maxWidth: 150);
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_JarvisTextPainter oldDelegate) {
    return currentEffect != oldDelegate.currentEffect;
  }
}

/// 贾维斯特效 — JARVIS 风格环形动画 + 终端
class JarvisAgentVisual implements AgentVisual {
  final TickerProvider vsync;

  static Future<FragmentProgram>? _shaderFuture;

  static Future<FragmentProgram> _ensureShaderLoaded() {
    _shaderFuture ??= FragmentProgram.fromAsset('shaders/jarvis.frag');
    return _shaderFuture!;
  }

  JarvisAgentVisual({required this.vsync}) {
    _userScrollController = ScrollController();
    _aiScrollController = ScrollController();
    _initAnimationControllers();
  }

  @override
  String get name => 'jarvis';

  // 退出冷却时间，防止误触
  bool _exitCooldown = false;
  DateTime? _lastExitTime;
  static const exitCooldownDuration = Duration(seconds: 3);

  // hide动画进行中，防止被新命令打断
  bool _isHiding = false;

  late AnimationController _outerRingController;
  late AnimationController _arcsController;
  late AnimationController _dataRingController;
  late AnimationController _innerRingController;
  late AnimationController _pulseController;

  double _outerRingAngle = 0;
  double _arcsAngle = 0;
  double _dataRingAngle = 0;
  double _innerRingAngle = 0;
  double _lastOuterValue = 0;
  double _lastArcsValue = 0;
  double _lastDataRingValue = 0;
  double _lastInnerRingValue = 0;

  String _currentEffect = 'idle';
  bool _isSpeaking = false; // 标记用户是否正在说话

  // 终端消息数据
  final List<String> _userMessages = [];
  final List<String> _aiMessages = [];
  String _currentUserText = '';
  String _currentAiText = '';

  late ScrollController _userScrollController;
  late ScrollController _aiScrollController;

  late AnimationController _ringOpacityController;
  late AnimationController _ringScaleController;
  late AnimationController _terminalSlideController;
  late AnimationController _leftTerminalSlideController;
  late AnimationController _rightTerminalSlideController;

  static const Color _jarvisBlue = Color(0xFF99FFFF);
  static const Color _terminalBackground = Color(0xCC00D9FF);

  void _initAnimationControllers() {
    _outerRingController = AnimationController(
      vsync: vsync,
      duration: const Duration(
        seconds: 10,
      ), // DEBUG: was 500, now 10 for visible rotation
    )..addListener(_updateOuterRingAngle);

    _arcsController = AnimationController(
      vsync: vsync,
      duration: const Duration(
        seconds: 10,
      ), // DEBUG: was 500, now 10 for visible rotation
    )..addListener(_updateArcsAngle);

    _dataRingController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 10),
    )..addListener(_updateDataRingAngle);

    _innerRingController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 5),
    )..addListener(_updateInnerRingAngle);

    _pulseController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _ringOpacityController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );

    _ringScaleController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
      lowerBound: 0.0,
      upperBound: 2.0,
    );

    _terminalSlideController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
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

    _outerRingController.repeat();
    _arcsController.repeat();
    _dataRingController.repeat();
    _innerRingController.repeat();
  }

  @override
  void handleCommand(String command) {
    print('Received command: $command');
    // hide动画进行中，只响应wake命令
    if (_isHiding && command != 'wake') {
      print('Ignoring command during hide animation: $command');
      return;
    }
    // 收到任何非 hide 命令，重置自动隐藏定时器
    if (command != 'hide' && _currentEffect == 'hide') {
      // 从隐藏状态恢复时，重置定时器
    }

    if (command == 'wake') {
      _isHiding = false;
      _currentEffect = 'wake';
      print('Set effect to: wake');
      _ringOpacityController.forward();
      _ringScaleController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else if (command == 'reset_scale') {
      // 用户讲完话，恢复特效大小（从 1.1 回到 1）
      _isSpeaking = false;
      if (_ringScaleController.value > 1.0) {
        _ringScaleController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (command == 'creating_session') {
      _currentEffect = 'creating_session';
    } else if (command == 'session_created') {
      _currentEffect = 'session_created';
    } else if (command == 'processing') {
      _currentEffect = 'processing';
    } else if (command == 'success') {
      _currentEffect = 'success';
    } else if (command == 'error') {
      _currentEffect = 'error';
    } else if (command == 'hide') {
      _currentEffect = 'hide';
      _isSpeaking = false;
      _isHiding = true;
      print('Set effect to: hide');
      // 监听动画状态，等待完成后清除消息
      void onComplete(AnimationStatus status) {
        if (status == AnimationStatus.dismissed && _isHiding) {
          _ringOpacityController.removeStatusListener(onComplete);
          _userMessages.clear();
          _aiMessages.clear();
          _currentUserText = '';
          _currentAiText = '';
          _isHiding = false;
        }
      }

      _ringOpacityController.addStatusListener(onComplete);
      // 启动反向动画
      _ringOpacityController.reverse();
      _ringScaleController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInCubic,
      );
      _leftTerminalSlideController.reverse();
      _rightTerminalSlideController.reverse();
    } else if (command.startsWith('user:')) {
      final text = command.substring(5);
      // 用户讲话，从当前值平滑变到 1.1（只触发一次）
      if (text.isNotEmpty && !_isSpeaking) {
        _isSpeaking = true;
        _ringScaleController.animateTo(
          1.1,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
      // 空消息不处理（避免触发动画）
      if (text.isEmpty) return;
      _currentEffect = 'user_text';
      // 检查是否包含关系（流式追加）
      if (_currentUserText.isNotEmpty && text.startsWith(_currentUserText)) {
        // 流式传输中，不保存历史，只更新当前文本
        _currentUserText = text;
      } else {
        // 新对话，将之前的转为历史
        if (_currentUserText.isNotEmpty) {
          _userMessages.add(_currentUserText);
        }
        _currentUserText = text;
        // 有文字时滑入右侧终端
        if (_rightTerminalSlideController.value == 0) {
          _rightTerminalSlideController.forward();
        }
      }
      // 流式传输时滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_userScrollController.hasClients) {
          _userScrollController.jumpTo(
            _userScrollController.position.maxScrollExtent,
          );
        }
      });
    } else if (command.startsWith('ai:')) {
      // AI 开始说话，恢复 scale
      _isSpeaking = false;
      if (_ringScaleController.value > 1.0) {
        _ringScaleController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      _currentEffect = 'ai_text';
      final text = command.substring(3);
      // 检查是否包含关系（流式追加）
      if (_currentAiText.isNotEmpty && text.startsWith(_currentAiText)) {
        // 流式传输中，不保存历史，只更新当前文本
        _currentAiText = text;
      } else {
        // 新对话，将之前的转为历史
        if (_currentAiText.isNotEmpty) {
          _aiMessages.add(_currentAiText);
        }
        _currentAiText = text;
        // 有文字时滑入左侧终端
        if (_leftTerminalSlideController.value == 0) {
          _leftTerminalSlideController.forward();
        }
      }
      // 流式传输时滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_aiScrollController.hasClients) {
          _aiScrollController.jumpTo(
            _aiScrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  void _updateOuterRingAngle() {
    final delta = _outerRingController.value - _lastOuterValue;
    _lastOuterValue = _outerRingController.value;
    final speedMultiplier =
        1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _outerRingAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _outerRingAngle += delta * speedMultiplier;
    }
  }

  void _updateArcsAngle() {
    final delta = _arcsController.value - _lastArcsValue;
    _lastArcsValue = _arcsController.value;
    final speedMultiplier =
        1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _arcsAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _arcsAngle += delta * speedMultiplier;
    }
  }

  void _updateDataRingAngle() {
    final delta = _dataRingController.value - _lastDataRingValue;
    _lastDataRingValue = _dataRingController.value;
    final speedMultiplier =
        1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _dataRingAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _dataRingAngle += delta * speedMultiplier;
    }
  }

  void _updateInnerRingAngle() {
    final delta = _innerRingController.value - _lastInnerRingValue;
    _lastInnerRingValue = _innerRingController.value;
    final speedMultiplier =
        1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _innerRingAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _innerRingAngle += delta * speedMultiplier;
    }
  }

  @override
  void dispose() {
    _userScrollController.dispose();
    _aiScrollController.dispose();
    _ringOpacityController.dispose();
    _ringScaleController.dispose();
    _terminalSlideController.dispose();
    _leftTerminalSlideController.dispose();
    _rightTerminalSlideController.dispose();
    _outerRingController.dispose();
    _arcsController.dispose();
    _dataRingController.dispose();
    _innerRingController.dispose();
    _pulseController.dispose();
  }

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

  @override
  Widget buildEffects(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final size = 300.0;

    double effectStateIndex() {
      switch (_currentEffect) {
        case 'success':
          return 1.0;
        case 'error':
          return 2.0;
        default:
          return 0.0;
      }
    }

    return Center(
      child: AnimatedBuilder(
        animation: _ringOpacityController,
        builder: (context, child) {
          return Opacity(
            opacity: _ringOpacityController.value,
            child: AnimatedBuilder(
              animation: _ringScaleController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _ringScaleController.value,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return SizedBox(
                        width: size,
                        height: size,
                        child: Stack(
                          children: [
                            FutureBuilder<FragmentProgram>(
                              future: _ensureShaderLoaded(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const SizedBox();
                                }
                                return CustomPaint(
                                  size: Size(size, size),
                                  painter: _JarvisShaderPainter(
                                    program: snapshot.data!,
                                    outerRingRotation:
                                        _outerRingAngle * 2 * math.pi,
                                    arcsRotation: _arcsAngle * 2 * math.pi,
                                    dataRingRotation:
                                        _dataRingAngle * 2 * math.pi,
                                    innerRingRotation:
                                        _innerRingAngle * 2 * math.pi,
                                    pulseValue: _pulseController.value,
                                    speakingScale:
                                        (_ringScaleController.value - 1.0)
                                            .clamp(0.0, 0.1) *
                                        10,
                                    effectState: effectStateIndex(),
                                  ),
                                );
                              },
                            ),
                            Center(
                              child: CustomPaint(
                                size: Size(size, size),
                                painter: _JarvisTextPainter(
                                  currentEffect: _currentEffect,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
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

    // 历史消息（旧的在前）
    for (int i = 0; i < messages.length; i++) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            messages[i],
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // 分隔线
    if (items.isNotEmpty) {
      items.add(const Divider(color: Colors.white24, height: 16));
    }

    // 当前流式文本（最后一项）
    if (currentText.isNotEmpty) {
      items.add(
        Text(
          currentText,
          style: const TextStyle(
            color: Colors.white,
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
            color: Colors.white38,
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
        color: _terminalBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _jarvisBlue.withAlpha(200), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: ListView(
        controller: scrollController,
        shrinkWrap: true,
        reverse: false,
        children: items,
      ),
    );
  }
}
