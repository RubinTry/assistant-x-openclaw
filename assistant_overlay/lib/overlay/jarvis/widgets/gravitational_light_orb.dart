import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Flutter-native reproduction of the gravitational light orb.
///
/// The visual is rendered by a runtime fragment shader, keeping the animated
/// simplex-noise edge and additive-looking cyan/blue/violet glow on the GPU.
class GravitationalLightOrb extends StatefulWidget {
  const GravitationalLightOrb({
    super.key,
    this.coreColor = const Color(0xFFC7E8FF),
    this.glowColor = const Color(0xFF2E6BEA),
    this.accentColor = const Color(0xFF6B3DDB),
    this.mistColor = const Color(0xFF578FFF),
    this.orbScale = 1,
  }) : assert(orbScale > 0);

  final Color coreColor;
  final Color glowColor;
  final Color accentColor;
  final Color mistColor;

  /// Orb diameter relative to the shader canvas. `1` matches the source effect.
  final double orbScale;

  @override
  State<GravitationalLightOrb> createState() => _GravitationalLightOrbState();
}

class _GravitationalLightOrbState extends State<GravitationalLightOrb>
    with TickerProviderStateMixin {
  static const _shaderAsset = 'shaders/gravitational_light_orb.frag';

  late final AnimationController _timeController;
  late final AnimationController _revealController;
  late final Animation<double> _revealOpacity;
  late final Animation<double> _revealScale;
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 10),
    )..repeat();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    final revealCurve = CurvedAnimation(
      parent: _revealController,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );
    _revealOpacity = revealCurve;
    _revealScale = Tween<double>(begin: 1.015, end: 1).animate(revealCurve);
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(_shaderAsset);
      if (!mounted) return;
      setState(() => _program = program);
      _revealController.forward(from: 0);
    } catch (error, stackTrace) {
      debugPrint('Failed to load gravitational light orb shader: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    if (program == null) return const SizedBox.expand();

    return RepaintBoundary(
      child: FadeTransition(
        opacity: _revealOpacity,
        child: ScaleTransition(
          scale: _revealScale,
          child: CustomPaint(
            painter: _GravitationalLightOrbPainter(
              program: program,
              time: _timeController,
              coreColor: widget.coreColor,
              glowColor: widget.glowColor,
              accentColor: widget.accentColor,
              mistColor: widget.mistColor,
              orbScale: widget.orbScale,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _GravitationalLightOrbPainter extends CustomPainter {
  _GravitationalLightOrbPainter({
    required this.program,
    required this.time,
    required this.coreColor,
    required this.glowColor,
    required this.accentColor,
    required this.mistColor,
    required this.orbScale,
  }) : super(repaint: time);

  final ui.FragmentProgram program;
  final Animation<double> time;
  final Color coreColor;
  final Color glowColor;
  final Color accentColor;
  final Color mistColor;
  final double orbScale;

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
      ..setFloat(0, time.value * 600)
      ..setFloat(1, size.width)
      ..setFloat(2, size.height);
    _setColor(shader, 3, coreColor);
    _setColor(shader, 6, glowColor);
    _setColor(shader, 9, accentColor);
    _setColor(shader, 12, mistColor);
    shader.setFloat(15, orbScale);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _GravitationalLightOrbPainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.time != time ||
        oldDelegate.coreColor != coreColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.mistColor != mistColor ||
        oldDelegate.orbScale != orbScale;
  }
}
