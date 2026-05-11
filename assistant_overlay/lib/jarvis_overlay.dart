import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:assistant_overlay/jarvis_rings_windows.dart';
import 'agent_visual.dart';

class JarvisRingsPainter extends CustomPainter {
  final double outerRingRotation;
  final double arcsRotation;
  final double dataRingRotation;
  final double innerRingRotation;
  final double pulseValue;
  final String currentEffect;
  final double speakingScale;

  JarvisRingsPainter({
    required this.outerRingRotation,
    required this.arcsRotation,
    required this.dataRingRotation,
    required this.innerRingRotation,
    required this.pulseValue,
    required this.currentEffect,
    this.speakingScale = 0.0,
  });

  Color get primaryColor {
    switch (currentEffect) {
      case 'success':
        return const Color(0xFF00FF66);
      case 'error':
        return const Color(0xFFFF4444);
      default:
        return const Color(0xFF5FFFFF);
    }
  }

  Color get primaryColorDim {
    switch (currentEffect) {
      case 'success':
        return const Color(0x8800FF66);
      case 'error':
        return const Color(0x88FF4444);
      default:
        return const Color(0x885FFFFF);
    }
  }

  Color get primaryColorLight {
    switch (currentEffect) {
      case 'success':
        return const Color(0xFFAAFFBB);
      case 'error':
        return const Color(0xFFFF8888);
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  double get opacity {
    if (currentEffect == 'hide' || currentEffect == 'idle') {
      return 0.0;
    }
    return 1.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity == 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    _paintOuterRing(canvas, center, maxRadius);
    _paintArcsLayer(canvas, center, maxRadius);
    _paintDataRing(canvas, center, maxRadius);
    _paintInnerRing(canvas, center, maxRadius);
    _paintCenterCore(canvas, center, maxRadius);
    _paintCenterText(canvas, center);
  }

  void _paintOuterRing(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.95;

    final ringPaint = Paint()
      ..color = primaryColorDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius, ringPaint);

    final tickPaint = Paint()
      ..color = primaryColorDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 60; i++) {
      final angle = (i / 60) * 2 * math.pi + outerRingRotation;
      final innerR = radius - 5;
      final outerR = radius;
      final start = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }

    final majorTickPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);

    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi + outerRingRotation;
      final innerR = radius - 12;
      final outerR = radius;
      final start = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      canvas.drawLine(start, end, majorTickPaint);
    }

    final glowPaint = Paint()
      ..color = primaryColor.withAlpha(
        (50 + pulseValue * 30 + speakingScale * 80).toInt(),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 + speakingScale * 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
    canvas.drawCircle(center, radius * (1.0 + speakingScale * 0.02), glowPaint);
  }

  void _paintArcsLayer(Canvas canvas, Offset center, double maxRadius) {
    final radius1 = maxRadius * 0.82;
    final radius2 = maxRadius * 0.75;
    final radius3 = maxRadius * 0.68;

    final arcPaint1 = Paint()
      ..color = primaryColorDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);

    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * math.pi + arcsRotation;
      final arcLength = math.pi / 12;
      final rect = Rect.fromCircle(center: center, radius: radius1);
      canvas.drawArc(rect, angle, arcLength, false, arcPaint1);
    }

    final arcPaint2 = Paint()
      ..color = primaryColor.withAlpha(220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);

    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * math.pi - arcsRotation * 0.5;
      final arcLength = math.pi / 20;
      final rect = Rect.fromCircle(center: center, radius: radius2);
      canvas.drawArc(rect, angle, arcLength, false, arcPaint2);
    }

    final arcPaint3 = Paint()
      ..color = primaryColorLight.withAlpha(200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4);

    for (int i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * math.pi + arcsRotation * 0.3;
      final arcLength = math.pi / 30;
      final rect = Rect.fromCircle(center: center, radius: radius3);
      canvas.drawArc(rect, angle, arcLength, false, arcPaint3);
    }
  }

  void _paintDataRing(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.55;

    final ringPaint = Paint()
      ..color = primaryColor.withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius, ringPaint);

    final tickPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 36; i++) {
      final angle = (i / 36) * 2 * math.pi + dataRingRotation;
      final innerR = radius - 8;
      final outerR = radius;
      final start = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }

    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi + dataRingRotation;
      final dotR = radius - 15;
      final dotCenter = Offset(
        center.dx + dotR * math.cos(angle),
        center.dy + dotR * math.sin(angle),
      );

      final brightness = ((math.sin(dataRingRotation * 3 + i) + 1) / 2).abs();
      final dotPaint = Paint()
        ..color = primaryColor.withAlpha((150 + brightness * 105).toInt())
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 5 + brightness * 6);

      canvas.drawCircle(dotCenter, 4 + brightness * 2, dotPaint);
    }

    final pulseRingPaint = Paint()
      ..color = primaryColor.withAlpha(
        (80 + pulseValue * 50 + speakingScale * 100).toInt(),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 + speakingScale * 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10);
    canvas.drawCircle(
      center,
      radius * (1.02 + pulseValue * 0.02 + speakingScale * 0.05),
      pulseRingPaint,
    );
  }

  void _paintInnerRing(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.38;

    final ringPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);
    canvas.drawCircle(center, radius, ringPaint);

    final innerRingPaint = Paint()
      ..color = primaryColor.withAlpha(200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius * 0.85, innerRingPaint);

    final chevronPaint = Paint()
      ..color = primaryColorLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5);

    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * math.pi + innerRingRotation;
      final r = radius * 0.7;
      final size = maxRadius * 0.06;

      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      final perpAngle = angle + math.pi / 2;
      final p1 = Offset(
        x + size * math.cos(perpAngle),
        y + size * math.sin(perpAngle),
      );
      final p2 = Offset(x, y);
      final p3 = Offset(
        x - size * math.cos(perpAngle),
        y - size * math.sin(perpAngle),
      );

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy);
      canvas.drawPath(path, chevronPaint);
    }

    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5);

    for (int i = 0; i < 4; i++) {
      final angle = (i / 4) * 2 * math.pi + innerRingRotation * 0.5;
      final dotR = radius * 1.15;
      final dotCenter = Offset(
        center.dx + dotR * math.cos(angle),
        center.dy + dotR * math.sin(angle),
      );
      canvas.drawCircle(dotCenter, 5, dotPaint);
    }
  }

  void _paintCenterCore(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.15;

    final glowPaint = Paint()
      ..color = primaryColor.withAlpha(
        (20 + pulseValue * 15 + speakingScale * 50).toInt(),
      )
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 15);
    canvas.drawCircle(center, radius * (1.8 + speakingScale * 0.5), glowPaint);

    final corePaint = Paint()
      ..color = primaryColor.withAlpha(60)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, corePaint);

    final coreRingPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5);
    canvas.drawCircle(center, radius, coreRingPaint);

    final innerCorePaint = Paint()
      ..color = primaryColorLight
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
    canvas.drawCircle(center, radius * 0.5, innerCorePaint);
  }

  void _paintCenterText(Canvas canvas, Offset center) {
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
  bool shouldRepaint(covariant JarvisRingsPainter oldDelegate) {
    return outerRingRotation != oldDelegate.outerRingRotation ||
        arcsRotation != oldDelegate.arcsRotation ||
        dataRingRotation != oldDelegate.dataRingRotation ||
        innerRingRotation != oldDelegate.innerRingRotation ||
        pulseValue != oldDelegate.pulseValue ||
        currentEffect != oldDelegate.currentEffect ||
        speakingScale != oldDelegate.speakingScale;
  }
}

/// 贾维斯特效 — JARVIS 风格环形动画 + 终端
class JarvisAgentVisual implements AgentVisual {
  final TickerProvider vsync;

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

  static const Color _jarvisBlue = Color(0xFF66FFFF);
  static const Color _terminalBackground = Color(0xFF0CDDFF);

  void _initAnimationControllers() {
    _outerRingController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 30),
    )..addListener(_updateOuterRingAngle);

    _arcsController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 30),
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
      // 立即清空消息，不依赖动画回调
      _userMessages.clear();
      _aiMessages.clear();
      _currentUserText = '';
      _currentAiText = '';
      // 监听动画状态，动画完成后重置 _isHiding
      void onComplete(AnimationStatus status) {
        if (status == AnimationStatus.dismissed && _isHiding) {
          _ringOpacityController.removeStatusListener(onComplete);
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
    final speedMultiplier = 1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _outerRingAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _outerRingAngle += delta * speedMultiplier;
    }
  }

  void _updateArcsAngle() {
    final delta = _arcsController.value - _lastArcsValue;
    _lastArcsValue = _arcsController.value;
    final speedMultiplier = 1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _arcsAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _arcsAngle += delta * speedMultiplier;
    }
  }

  void _updateDataRingAngle() {
    final delta = _dataRingController.value - _lastDataRingValue;
    _lastDataRingValue = _dataRingController.value;
    final speedMultiplier = 1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
    if (delta < 0) {
      _dataRingAngle += (delta + 1.0) * speedMultiplier;
    } else {
      _dataRingAngle += delta * speedMultiplier;
    }
  }

  void _updateInnerRingAngle() {
    final delta = _innerRingController.value - _lastInnerRingValue;
    _lastInnerRingValue = _innerRingController.value;
    final speedMultiplier = 1.0 + (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 30;
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
                        child: CustomPaint(
                          painter: Platform.isWindows
                              ? JarvisRingsPainterWindows(
                            outerRingRotation:
                            (_outerRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            arcsRotation:
                            (_arcsAngle * 2 * math.pi) %
                                (2 * math.pi),
                            dataRingRotation:
                            (_dataRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            innerRingRotation:
                            (_innerRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            pulseValue: _pulseController.value,
                            currentEffect: _currentEffect,
                            speakingScale:
                            (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 10,
                          )
                              : JarvisRingsPainter(
                            outerRingRotation:
                            (_outerRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            arcsRotation:
                            (_arcsAngle * 2 * math.pi) %
                                (2 * math.pi),
                            dataRingRotation:
                            (_dataRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            innerRingRotation:
                            (_innerRingAngle * 2 * math.pi) %
                                (2 * math.pi),
                            pulseValue: _pulseController.value,
                            currentEffect: _currentEffect,
                            speakingScale:
                            (_ringScaleController.value - 1.0).clamp(0.0, 0.1) * 10,
                          ),
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
        color: _terminalBackground.withAlpha(100),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _jarvisBlue.withAlpha(150), width: 0),
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
