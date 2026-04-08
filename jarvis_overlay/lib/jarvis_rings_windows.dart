import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class JarvisRingsPainterWindows extends CustomPainter {
  final double outerRingRotation;
  final double arcsRotation;
  final double dataRingRotation;
  final double innerRingRotation;
  final double pulseValue;
  final String currentEffect;

  JarvisRingsPainterWindows({
    required this.outerRingRotation,
    required this.arcsRotation,
    required this.dataRingRotation,
    required this.innerRingRotation,
    required this.pulseValue,
    required this.currentEffect,
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
      ..strokeWidth = 6;
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
      ..strokeCap = StrokeCap.round;

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
      ..color = primaryColor.withAlpha((50 + pulseValue * 30).toInt())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, glowPaint);
  }

  void _paintArcsLayer(Canvas canvas, Offset center, double maxRadius) {
    final radius1 = maxRadius * 0.82;
    final radius2 = maxRadius * 0.75;
    final radius3 = maxRadius * 0.68;

    final arcPaint1 = Paint()
      ..color = primaryColorDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

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
      ..strokeCap = StrokeCap.round;

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
      ..strokeCap = StrokeCap.round;

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
      ..strokeWidth = 3;
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
        ..style = PaintingStyle.fill;

      canvas.drawCircle(dotCenter, 4 + brightness * 2, dotPaint);
    }

    final pulseRingPaint = Paint()
      ..color = primaryColor.withAlpha((80 + pulseValue * 50).toInt())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(
      center,
      radius * (1.02 + pulseValue * 0.02),
      pulseRingPaint,
    );
  }

  void _paintInnerRing(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.38;

    final ringPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
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
      ..strokeCap = StrokeCap.round;

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
      ..style = PaintingStyle.fill;

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
      ..color = primaryColor.withAlpha((20 + pulseValue * 15).toInt())
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 1.8, glowPaint);

    final corePaint = Paint()
      ..color = primaryColor.withAlpha(60)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, corePaint);

    final coreRingPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, coreRingPaint);

    final innerCorePaint = Paint()
      ..color = primaryColorLight
      ..style = PaintingStyle.fill;
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
  bool shouldRepaint(covariant JarvisRingsPainterWindows oldDelegate) {
    return outerRingRotation != oldDelegate.outerRingRotation ||
        arcsRotation != oldDelegate.arcsRotation ||
        dataRingRotation != oldDelegate.dataRingRotation ||
        innerRingRotation != oldDelegate.innerRingRotation ||
        pulseValue != oldDelegate.pulseValue ||
        currentEffect != oldDelegate.currentEffect;
  }
}
