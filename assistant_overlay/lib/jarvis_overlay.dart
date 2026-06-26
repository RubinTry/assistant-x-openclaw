import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:assistant_overlay/jarvis_rings_windows.dart';
import 'package:flutter/services.dart';
import 'package:system_info2/system_info2.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'agent_visual.dart';
import 'hud_terminal_shell.dart';

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
        return const Color(0xFF12B9FF);
    }
  }

  Color get primaryColorDim {
    switch (currentEffect) {
      case 'success':
        return const Color(0x8800FF66);
      case 'error':
        return const Color(0x88FF4444);
      default:
        return const Color(0xFF12B9FF);
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
          fontSize: 16,
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
  final double _jarvisRingSize = 240;

  String _currentEffect = 'idle';
  bool _isSpeaking = false; // 标记用户是否正在说话

  // 终端消息数据
  final List<String> _userMessages = [];
  final List<String> _aiMessages = [];

  // 与 _userMessages/_aiMessages 一一对应的时间戳（HH:mm），追加消息时同步写入
  final List<String> _userTimes = [];
  final List<String> _aiTimes = [];
  String _currentUserText = '';
  String _currentAiText = '';

  static String _hm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  late ScrollController _userScrollController;
  late ScrollController _aiScrollController;

  late AnimationController _ringOpacityController;
  late AnimationController _ringScaleController;
  late AnimationController _terminalSlideController;
  late AnimationController _leftTerminalSlideController;
  late AnimationController _rightTerminalSlideController;


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

    // 流式滚动到底部辅助函数（嵌套 2 帧 postFrame）。
    // 提到 handleCommand 顶部，让 user/ai 两个分支共享同一份逻辑。
    // - 单帧 postFrame 在 paint 后立即跑，但 shrinkWrap ListView 的
    //   新 maxScrollExtent 还没回流到 ScrollPosition，jumpTo 跳到旧值
    // - 双帧：第一帧 setState→build，第二帧 ListView 完成自身 layout，
    //   新 maxScrollExtent 已就位，跳到底部才有效
    void scrollToBottomOnNextFrame(ScrollController c) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (c.hasClients) {
            c.jumpTo(c.position.maxScrollExtent);
          }
        });
      });
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
      // 用户讲完话，恢复特效大小（从 1.5 回到 1）
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
      _userTimes.clear();
      _aiTimes.clear();
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
      // 用户讲话，从当前值平滑变到 1.3（只触发一次）
      if (text.isNotEmpty && !_isSpeaking) {
        _isSpeaking = true;
        _ringScaleController.animateTo(
          1.3,
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
          _userTimes.add(_hm());
        }
        _currentUserText = text;
        // 有文字时滑入右侧终端
        if (_rightTerminalSlideController.value == 0) {
          _rightTerminalSlideController.forward();
        }
      }
      // 流式传输时滚动到底部（详见 handleCommand 顶部 scrollToBottomOnNextFrame 注释）
      scrollToBottomOnNextFrame(_userScrollController);
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
          _aiTimes.add(_hm());
        }
        _currentAiText = text;
        // 有文字时滑入左侧终端
        if (_leftTerminalSlideController.value == 0) {
          _leftTerminalSlideController.forward();
        }
      }
      // 流式传输时滚动到底部（同 user 分支）
      scrollToBottomOnNextFrame(_aiScrollController);
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
          margin: EdgeInsets.only(left: 80, top: screenHeight * 0.10),
          child: SizedBox(
            height: terminalHeight,
            child: _buildTerminal(
              screenWidth: screenWidth,
              messages: _aiMessages,
              times: _aiTimes,
              currentText: _currentAiText,
              title: 'J.A.R.V.I.S.',
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
          margin: EdgeInsets.only(right: 80, bottom: screenHeight * 0.10),
          child: SizedBox(
            height: terminalHeight,
            child: _buildTerminal(
              screenWidth: screenWidth,
              messages: _userMessages,
              times: _userTimes,
              currentText: _currentUserText,
              title: 'MESSAGE FEED',
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
    final size = 400.0;

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
                        child: JarvisSequencePlayer(
                          assetDir: 'assets/jarvis', // 只需要指定目录
                          assetSuffix: '.png',
                          fps: 30,
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

  // 单行：消息（左，自动换行）+ 时间戳（右，青色）
  //
  // 重要：消息文本不设 maxLines / ellipsis，让完整内容展示。
  // 终端历史本来就该让用户读完所有对话 —— 截断消息是误导。
  // 当前行（流式中）也不截断，否则用户看不到 AI 正在输出的完整回复。
  Widget _terminalRow(String msg, String time, {bool current = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: current ? Colors.white : Colors.white70,
                fontSize: 14,
                height: 1.35,
                fontWeight: current ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              time,
              style: TextStyle(color: Color(0xFF8CC1FA).withAlpha(150), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal({
    required double screenWidth,
    required List<String> messages,
    required List<String> times,
    required String currentText,
    required String title,
    required double maxHeight,
    required ScrollController scrollController,
  }) {
    final List<Widget> items = [];

    // 历史消息（旧的在前）+ 对应时间戳
    for (int i = 0; i < messages.length; i++) {
      items.add(_terminalRow(messages[i], i < times.length ? times[i] : ''));
    }

    // 当前流式文本（最后一项，高亮）
    if (currentText.isNotEmpty) {
      items.add(_terminalRow(currentText, _hm(), current: true));
    } else if (items.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            '...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return HudTerminalShell(
      title: title,
      titleIcon: Image.asset("assets/ico-jarvis.png", width: 14, height: 14),
      showStatusDot: true,
      width: screenWidth / 6,
      maxHeight: maxHeight,
      child: ListView( 
        controller: scrollController,
        shrinkWrap: true,
        reverse: false,
        physics: const ClampingScrollPhysics(),
        children: items,
      ),
    );
  }

  @override
  Widget buildOtherOne(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    return Positioned(
      right: 80 + (screenWidth / 6 - _jarvisRingSize) / 2,
      top: screenHeight * 0.10,
      child: AnimatedBuilder(
        animation: _ringOpacityController,
        builder: (context, child) {
          return Opacity(
            opacity: _ringOpacityController.value,
            child: AnimatedBuilder(
              animation: _ringScaleController,
              builder: (context, child) {
                return AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return SizedBox(
                      width: _jarvisRingSize,
                      height: _jarvisRingSize,
                      child: CustomPaint(
                        painter: Platform.isWindows
                            ? JarvisRingsPainterWindows(
                                outerRingRotation:
                                    (_outerRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                arcsRotation:
                                    (_arcsAngle * 2 * math.pi) % (2 * math.pi),
                                dataRingRotation:
                                    (_dataRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                innerRingRotation:
                                    (_innerRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                pulseValue: _pulseController.value,
                                currentEffect: _currentEffect,
                                speakingScale:
                                    (_ringScaleController.value - 1.0).clamp(
                                      0.0,
                                      0.1,
                                    ) *
                                    10,
                              )
                            : JarvisRingsPainter(
                                outerRingRotation:
                                    (_outerRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                arcsRotation:
                                    (_arcsAngle * 2 * math.pi) % (2 * math.pi),
                                dataRingRotation:
                                    (_dataRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                innerRingRotation:
                                    (_innerRingAngle * 2 * math.pi) %
                                    (2 * math.pi),
                                pulseValue: _pulseController.value,
                                currentEffect: _currentEffect,
                                speakingScale:
                                    (_ringScaleController.value - 1.0).clamp(
                                      0.0,
                                      0.1,
                                    ) *
                                    10,
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildOtherTwo(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final double terminalHeight = screenHeight / 3;
    return Positioned(
      left: 80,
      bottom: screenHeight * 0.10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 显隐跟随 _ringOpacityController，与环形/序列帧等特效一致
          AnimatedBuilder(
            animation: _ringOpacityController,
            builder: (context, child) => Opacity(
              opacity: _ringOpacityController.value,
              child: child,
            ),
            child: HudTerminalShell(
              title: 'SYSTEM STATUS',
              titleIcon: Image.asset("assets/ico-jarvis.png", width: 14, height: 14),
              width: screenWidth / 6,
              maxHeight: double.infinity,
              child: const _SystemStatusPanel(),
            ),
          ),
          AnimatedBuilder(
            animation: _ringOpacityController,
            builder: (context, child) {
              return Opacity(
                opacity: _ringOpacityController.value,
                child: AnimatedBuilder(
                  animation: _ringScaleController,
                  builder: (context, child) {
                    return AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return SizedBox(
                          width: terminalHeight / 3 * 2,
                          height: terminalHeight / 3 * 2,
                          child: JarvisSequencePlayer(
                            assetDir: 'assets/ironman', // 只需要指定目录
                            assetSuffix: '.png',
                            fps: 30,
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class JarvisSequencePlayer extends StatefulWidget {
  final int fps;
  final String assetDir; // 资源目录，例如: 'assets/jarvis'
  final String assetSuffix; // 文件后缀，例如: '.png'

  const JarvisSequencePlayer({
    super.key,
    this.fps = 60,
    required this.assetDir,
    this.assetSuffix = '.png',
  });

  @override
  State<JarvisSequencePlayer> createState() => _JarvisSequencePlayerState();
}

class _JarvisSequencePlayerState extends State<JarvisSequencePlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<ui.Image> _cachedFrames = [];
  List<String> _framePaths = []; // 动态获取的文件路径列表
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _initSequence();
  }

  // 1. 异步初始化：先动态读取文件数量，再加载图片
  Future<void> _initSequence() async {
    await _loadFramePaths();
    if (_framePaths.isNotEmpty) {
      await _decodeAllFrames();
      // 动态计算动画时长
      final duration = Duration(
        milliseconds: (_framePaths.length / widget.fps * 1000).round(),
      );
      _controller = AnimationController(vsync: this, duration: duration)
        ..repeat();
      if (mounted) setState(() => _isLoaded = true);
    }
  }

  // 2. 动态扫描目录获取文件列表（核心逻辑）
  Future<void> _loadFramePaths() async {
    try {
      // 【最佳实践】：使用 DefaultAssetBundle 替代 rootBundle
      // 这样不仅符合官方规范，还能完美兼容本地化和测试场景
      final assetManifest = await AssetManifest.loadFromAssetBundle(
        DefaultAssetBundle.of(context),
      );
      final allAssets = assetManifest.listAssets();

      // 过滤出目标目录下的文件，并按文件名排序
      _framePaths =
          allAssets
              .where(
                (path) =>
                    path.startsWith(widget.assetDir) &&
                    path.endsWith(widget.assetSuffix),
              )
              .toList()
            ..sort();
    } catch (e) {
      debugPrint('读取资源目录失败: $e');
    }
  }

  // 3. 预加载解码所有帧
  Future<void> _decodeAllFrames() async {
    for (final path in _framePaths) {
      try {
        final ByteData data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        _cachedFrames.add(frame.image);
      } catch (e) {
        debugPrint('解码帧失败: $path');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (var img in _cachedFrames) {
      img.dispose(); // 释放底层内存
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) return const SizedBox.shrink(); // 加载期间不占空间或显示Loading

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 动态获取总帧数，防止越界
        final index = (_controller.value * _cachedFrames.length).floor().clamp(
          0,
          _cachedFrames.length - 1,
        );
        return CustomPaint(
          painter: _SequencePainter(_cachedFrames[index]),
          size: Size.infinite,
        );
      },
    );
  }
}

// 底层画布绘制器
class _SequencePainter extends CustomPainter {
  final ui.Image frame;

  _SequencePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      frame,
      Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _SequencePainter oldDelegate) =>
      oldDelegate.frame != frame;
}

/// 终端框 HUD 边框已抽离到 `hud_terminal_shell.dart`，本文件不再持有。

/// SYSTEM STATUS 面板：用已接入的包展示可获取的系统信息（定时轮询）。
/// MEMORY/STORAGE ← system_info2；BATTERY ← battery_plus；
/// NETWORK ← connectivity_plus + network_info_plus。
/// 单项指标快照（百分比 + 历史 + 数值后缀 + 已用/总量明细），ValueNotifier 的载体。
class _Metric {
  final double pct;
  final List<double> hist;
  final String suffix;
  final String detail; // 如 "14.9 / 24 GB"
  const _Metric(this.pct, this.hist, {this.suffix = '', this.detail = ''});
}

/// 网络项快照（连接 + 上下行速率 KB/s）。
class _Net {
  final IconData icon;
  final String main;
  final String ip;
  final double down; // KB/s
  final double up; // KB/s
  const _Net(this.icon, this.main, this.ip, {this.down = 0, this.up = 0});
}

class _SystemStatusPanel extends StatefulWidget {
  const _SystemStatusPanel();

  @override
  State<_SystemStatusPanel> createState() => _SystemStatusPanelState();
}

class _SystemStatusPanelState extends State<_SystemStatusPanel> {
  static const Color _cyan = Color(0xFF66FFFF);
  static const Color _light = Color(0xFF8CF6FF);

  final Battery _battery = Battery();
  final NetworkInfo _netInfo = NetworkInfo();
  final Connectivity _conn = Connectivity();
  Timer? _timer;

  // 各指标用独立 ValueNotifier 驱动，配合 ValueListenableBuilder 局部刷新，
  // 避免每次轮询 setState 整个面板重建。
  final ValueNotifier<_Metric> _memN = ValueNotifier(const _Metric(0, []));
  final ValueNotifier<_Metric> _storN = ValueNotifier(const _Metric(0, []));
  final ValueNotifier<_Metric> _batN = ValueNotifier(const _Metric(0, []));
  final ValueNotifier<_Net> _netN =
      ValueNotifier(const _Net(Icons.help_outline, '—', ''));

  final List<double> _memHist = [];
  final List<double> _storHist = [];
  final List<double> _batHist = [];

  // 网络速率：记录上次累计字节 + 时间，差分算 KB/s
  int _lastNetIn = -1, _lastNetOut = -1;
  DateTime _lastNetAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _poll();
    // 面板数据定期更新一次
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _memN.dispose();
    _storN.dispose();
    _batN.dispose();
    _netN.dispose();
    super.dispose();
  }

  void _push(List<double> h, double v) {
    h.add(v);
    if (h.length > 40) h.removeAt(0);
  }

  Future<void> _poll() async {
    double mem = _memN.value.pct, stor = _storN.value.pct;
    String memDetail = _memN.value.detail, storDetail = _storN.value.detail;
    // macOS：system_info2 4.1.0 的实现有 bug——getTotalPhysicalMemory 把已是字节的
    // hw.memsize 又乘了一遍 hw.pagesize（24G 会显示成 39 万 G），存储接口在 macOS
    // 直接 notSupportedError。故 macOS 走原生 sysctl/vm_stat/df 自算，其余平台仍用
    // system_info2。
    try {
      final m = Platform.isMacOS ? await _macMem() : _sysInfoMem();
      if (m != null) {
        final used = m[0], total = m[1];
        mem = (used / total * 100).clamp(0, 100).toDouble();
        memDetail = '${_fmtGB(used)} / ${_fmtGB(total)} GB';
      }
    } catch (_) {}
    try {
      final s = Platform.isMacOS ? await _macStorage() : _sysInfoStorage();
      if (s != null) {
        final used = s[0], total = s[1];
        stor = (used / total * 100).clamp(0, 100).toDouble();
        storDetail = '${_fmtGB(used)} / ${_fmtGB(total)} GB';
      }
    } catch (_) {}

    int bat = _batN.value.pct.round();
    bool charging = _batN.value.suffix.isNotEmpty;
    try {
      bat = await _battery.batteryLevel;
      final st = await _battery.batteryState;
      charging = st == BatteryState.charging || st == BatteryState.full;
    } catch (_) {}

    String connLabel = 'Unknown';
    String wifiName = _netN.value.main, wifiIp = _netN.value.ip;
    try {
      connLabel = _labelOf(await _conn.checkConnectivity());
    } catch (_) {}
    try {
      final n = await _netInfo.getWifiName();
      final ip = await _netInfo.getWifiIP();
      wifiName = (n ?? '').replaceAll('"', '');
      wifiIp = ip ?? '';
    } catch (_) {}

    // 上下行速率：读累计字节，与上次差分算 KB/s
    double down = _netN.value.down, up = _netN.value.up;
    final nb = await _readNetBytes();
    final now = DateTime.now();
    if (nb != null) {
      if (_lastNetIn >= 0) {
        final dt = now.difference(_lastNetAt).inMilliseconds / 1000.0;
        if (dt > 0) {
          down = ((nb[0] - _lastNetIn) / dt / 1024).clamp(0, double.infinity);
          up = ((nb[1] - _lastNetOut) / dt / 1024).clamp(0, double.infinity);
        }
      }
      _lastNetIn = nb[0];
      _lastNetOut = nb[1];
      _lastNetAt = now;
    }

    if (!mounted) return;
    _push(_memHist, mem);
    _push(_storHist, stor);
    _push(_batHist, bat.toDouble());
    _memN.value =
        _Metric(mem, List<double>.from(_memHist), detail: memDetail);
    _storN.value =
        _Metric(stor, List<double>.from(_storHist), detail: storDetail);
    _batN.value = _Metric(
      bat.toDouble(),
      List<double>.from(_batHist),
      suffix: charging ? ' ⚡' : '',
    );
    _netN.value = _Net(
      _iconFor(connLabel),
      wifiName.isNotEmpty ? wifiName : connLabel,
      wifiIp,
      down: down,
      up: up,
    );
  }

  /// 非 macOS：用 system_info2 取 [已用, 总量] 字节；不可用返回 null。
  List<int>? _sysInfoMem() {
    final total = SysInfo.getTotalPhysicalMemory();
    if (total <= 0) return null;
    var avail = 0;
    try {
      avail = SysInfo.getAvailablePhysicalMemory();
    } catch (_) {}
    if (avail <= 0) {
      try {
        avail = SysInfo.getFreePhysicalMemory();
      } catch (_) {}
    }
    return [total - avail, total];
  }

  List<int>? _sysInfoStorage() {
    final total = SysInfo.getTotalStorage();
    final free = SysInfo.getFreeStorage();
    if (total <= 0) return null;
    return [total - free, total];
  }

  /// macOS 原生内存 [已用, 总量] 字节。总量取 hw.memsize（已是字节）。已用严格按
  /// 活动监视器“已使用内存”口径 = App Memory + Wired + Compressed，其中
  /// App Memory = 匿名页(Anonymous，即非文件缓存) − 可清除页(Purgeable)。
  /// 旧版用 active 会把文件缓存的活跃页也算进去，偏小且与活动监视器对不上。
  Future<List<int>?> _macMem() async {
    final total =
        int.tryParse((await Process.run('sysctl', ['-n', 'hw.memsize'])).stdout
                .toString()
                .trim()) ??
            0;
    if (total <= 0) return null;
    final vm = await Process.run('vm_stat', []);
    final out = vm.stdout.toString();
    final pageSize = int.tryParse(
            RegExp(r'page size of (\d+) bytes').firstMatch(out)?.group(1) ??
                '') ??
        4096;
    int pages(String key) {
      final m = RegExp('$key:\\s+(\\d+)').firstMatch(out);
      return m != null ? int.parse(m.group(1)!) : 0;
    }

    final anonymous = pages('Anonymous pages');
    final purgeable = pages('Pages purgeable');
    final wired = pages('Pages wired down');
    final compressed = pages('Pages occupied by compressor');
    final appMem = anonymous - purgeable; // App Memory
    final used = (appMem + wired + compressed) * pageSize;
    return [used.clamp(0, total).toInt(), total];
  }

  /// macOS 原生存储 [已用, 总量] 字节，经 df -k 根卷；失败返回 null。
  Future<List<int>?> _macStorage() async {
    final r = await Process.run('df', ['-k', '/']);
    final lines = r.stdout.toString().trim().split('\n');
    if (lines.length < 2) return null;
    final f = lines.last.trim().split(RegExp(r'\s+'));
    if (f.length < 4) return null;
    final total = (int.tryParse(f[1]) ?? 0) * 1024;
    final avail = (int.tryParse(f[3]) ?? 0) * 1024;
    if (total <= 0) return null;
    return [total - avail, total];
  }

  /// 读主网卡累计收发字节 [in, out]（仅 macOS，经 netstat）；失败返回 null。
  Future<List<int>?> _readNetBytes() async {
    if (!Platform.isMacOS) return null;
    try {
      final r = await Process.run('bash', [
        '-c',
        r'''i=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'); netstat -ibn 2>/dev/null | awk -v i="$i" '$1==i && $3 ~ /Link/ {print $7" "$10; exit}' '''
      ]);
      final parts = (r.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final inB = int.tryParse(parts[0]);
        final outB = int.tryParse(parts[1]);
        if (inB != null && outB != null) return [inB, outB];
      }
    } catch (_) {}
    return null;
  }

  static String _fmtGB(num bytes) =>
      (bytes / 1073741824).toStringAsFixed(1);

  static String _fmtRate(double kbs) {
    if (kbs >= 1024) return '${(kbs / 1024).toStringAsFixed(1)} MB/s';
    return '${kbs.toStringAsFixed(kbs < 10 ? 1 : 0)} KB/s';
  }

  String _labelOf(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi)) return 'WiFi';
    if (r.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (r.contains(ConnectivityResult.mobile)) return 'Mobile';
    if (r.contains(ConnectivityResult.vpn)) return 'VPN';
    if (r.contains(ConnectivityResult.none)) return 'Offline';
    return 'Unknown';
  }

  static IconData _iconFor(String label) {
    switch (label) {
      case 'WiFi':
        return Icons.wifi;
      case 'Ethernet':
        return Icons.lan_outlined;
      case 'Mobile':
        return Icons.signal_cellular_alt;
      case 'Offline':
        return Icons.wifi_off;
      default:
        return Icons.help_outline;
    }
  }

  Widget _gaugeRow(String label, _Metric m) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CustomPaint(painter: _GaugeRingPainter(m.pct / 100, _cyan)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _light,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${m.pct.round()}%${m.suffix}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (m.detail.isNotEmpty)
                Text(
                  m.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _cyan.withAlpha(160), fontSize: 10),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          height: 30,
          child: CustomPaint(painter: _SparklinePainter(m.hist, _cyan)),
        ),
      ],
    );
  }

  Widget _netRow(_Net n) {
    final sub = n.ip.isNotEmpty ? '${n.main} · ${n.ip}' : n.main;
    return Row(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Icon(n.icon, size: 22, color: _cyan),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'NETWORK',
                style: TextStyle(
                  color: _light,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '↓ ${_fmtRate(n.down)}   ↑ ${_fmtRate(n.up)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _cyan.withAlpha(160), fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double space = 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ValueListenableBuilder<_Metric>(
              valueListenable: _memN,
              builder: (_, m, __) => _gaugeRow('MEMORY', m),
            ),
            SizedBox(
              height: space,
            ),
            ValueListenableBuilder<_Metric>(
              valueListenable: _storN,
              builder: (_, m, __) => _gaugeRow('STORAGE', m),
            ),
            SizedBox(
              height: space,
            ),
            ValueListenableBuilder<_Metric>(
              valueListenable: _batN,
              builder: (_, m, __) => _gaugeRow('BATTERY', m),
            ),
            SizedBox(
              height: space,
            ),
            ValueListenableBuilder<_Net>(
              valueListenable: _netN,
              builder: (_, n, __) => _netRow(n),
            ),
          ],
        ),
      ],
    );
  }
}

/// 圆环进度表（背景暗环 + 亮色进度弧，从 12 点顺时针）。
class _GaugeRingPainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  _GaugeRingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 3;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = color.withAlpha(45),
    );
    final sweep = value.clamp(0.0, 1.0) * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = color.withAlpha(160)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugeRingPainter o) =>
      o.value != value || o.color != color;
}

/// 折线图（最近若干采样，0..100 归一化）。
class _SparklinePainter extends CustomPainter {
  final List<double> values; // 0..100
  final Color color;
  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final n = values.length;
    final dx = size.width / (n - 1);
    final path = Path();
    for (int i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 100.0) / 100.0;
      final x = dx * i;
      final y = size.height - v * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withAlpha(120)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withAlpha(220),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter o) =>
      o.values.length != values.length ||
      (values.isNotEmpty && o.values.last != values.last);
}
