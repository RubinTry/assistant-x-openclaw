import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class JarvisRingsShader extends StatefulWidget {
  const JarvisRingsShader({
    super.key,
    required this.outerRingRotation,
    required this.arcsRotation,
    required this.dataRingRotation,
    required this.innerRingRotation,
    required this.pulseValue,
    required this.currentEffect,
    this.speakingScale = 0,
    this.showLabel = true,
  });

  final double outerRingRotation;
  final double arcsRotation;
  final double dataRingRotation;
  final double innerRingRotation;
  final double pulseValue;
  final String currentEffect;
  final double speakingScale;
  final bool showLabel;

  @override
  State<JarvisRingsShader> createState() => _JarvisRingsShaderState();
}

class _JarvisRingsShaderState extends State<JarvisRingsShader> {
  static const _shaderAsset = 'shaders/jarvis_rings.frag';

  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(_shaderAsset);
      if (!mounted) return;
      setState(() => _program = program);
    } catch (error, stackTrace) {
      debugPrint('Failed to load JARVIS rings shader: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    if (program == null || _effectOpacity(widget.currentEffect) == 0) {
      return const SizedBox.expand();
    }

    final colors = _JarvisRingColors.forEffect(widget.currentEffect);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _JarvisRingsShaderPainter(
              program: program,
              outerRingRotation: widget.outerRingRotation,
              arcsRotation: widget.arcsRotation,
              dataRingRotation: widget.dataRingRotation,
              innerRingRotation: widget.innerRingRotation,
              pulseValue: widget.pulseValue,
              speakingScale: widget.speakingScale,
              primaryColor: colors.primary,
              dimColor: colors.dim,
              lightColor: colors.light,
            ),
          ),
          if (widget.showLabel)
            Center(
              child: Text(
                'J.A.R.V.I.S.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: colors.primary, blurRadius: 10),
                    Shadow(
                      color: colors.primary.withAlpha(150),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static double _effectOpacity(String currentEffect) {
    if (currentEffect == 'hide' || currentEffect == 'idle') return 0;
    return 1;
  }
}

class _JarvisRingColors {
  const _JarvisRingColors({
    required this.primary,
    required this.dim,
    required this.light,
  });

  final Color primary;
  final Color dim;
  final Color light;

  static _JarvisRingColors forEffect(String currentEffect) {
    switch (currentEffect) {
      case 'success':
        return const _JarvisRingColors(
          primary: Color(0xFF00FF66),
          dim: Color(0x8800FF66),
          light: Color(0xFFAAFFBB),
        );
      case 'error':
        return const _JarvisRingColors(
          primary: Color(0xFFFF4444),
          dim: Color(0x88FF4444),
          light: Color(0xFFFF8888),
        );
      default:
        return const _JarvisRingColors(
          primary: Color(0xFF12B9FF),
          dim: Color(0xFF12B9FF),
          light: Color(0xFFFFFFFF),
        );
    }
  }
}

class _JarvisRingsShaderPainter extends CustomPainter {
  const _JarvisRingsShaderPainter({
    required this.program,
    required this.outerRingRotation,
    required this.arcsRotation,
    required this.dataRingRotation,
    required this.innerRingRotation,
    required this.pulseValue,
    required this.speakingScale,
    required this.primaryColor,
    required this.dimColor,
    required this.lightColor,
  });

  final ui.FragmentProgram program;
  final double outerRingRotation;
  final double arcsRotation;
  final double dataRingRotation;
  final double innerRingRotation;
  final double pulseValue;
  final double speakingScale;
  final Color primaryColor;
  final Color dimColor;
  final Color lightColor;

  static double _channel(Color color, int shift) {
    return ((color.toARGB32() >> shift) & 0xff) / 255;
  }

  static void _setColor(ui.FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, _channel(color, 16))
      ..setFloat(index + 1, _channel(color, 8))
      ..setFloat(index + 2, _channel(color, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, outerRingRotation % (math.pi * 2))
      ..setFloat(3, arcsRotation % (math.pi * 2))
      ..setFloat(4, dataRingRotation % (math.pi * 2))
      ..setFloat(5, innerRingRotation % (math.pi * 2))
      ..setFloat(6, pulseValue.clamp(0.0, 1.0))
      ..setFloat(7, speakingScale.clamp(0.0, 1.0));
    _setColor(shader, 8, primaryColor);
    _setColor(shader, 11, dimColor);
    _setColor(shader, 14, lightColor);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _JarvisRingsShaderPainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.outerRingRotation != outerRingRotation ||
        oldDelegate.arcsRotation != arcsRotation ||
        oldDelegate.dataRingRotation != dataRingRotation ||
        oldDelegate.innerRingRotation != innerRingRotation ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.speakingScale != speakingScale ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.lightColor != lightColor;
  }
}
