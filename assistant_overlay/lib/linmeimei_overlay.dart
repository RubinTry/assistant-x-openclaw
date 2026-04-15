import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'agent_visual.dart';

class OrbRenderer extends StatefulWidget {
  final double time;

  const OrbRenderer({Key? key, required this.time}) : super(key: key);

  @override
  State<OrbRenderer> createState() => _OrbRendererState();
}

class _OrbRendererState extends State<OrbRenderer> {
  FragmentProgram? _program;

  @override
  void initState() {
    _loadShader();
    super.initState();
  }

  void _loadShader() async {
    final program = await FragmentProgram.fromAsset('shaders/orb_shader.frag');
    if (mounted) {
      setState(() {
        _program = program;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null) return SizedBox.expand();
    return CustomPaint(
      painter: _OrbPainter(program: _program!, time: widget.time),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final FragmentProgram program;
  final double time;

  _OrbPainter({required this.program, required this.time});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final shader = program.fragmentShader();
    shader.setFloat(0, time);
    shader.setFloat(1, canvasSize.width);
    shader.setFloat(2, canvasSize.height);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & canvasSize, paint);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) {
    return true;
  }
}

class LinMeimeiPet implements AgentVisual {
  final TickerProvider vsync;
  final VoidCallback onModelReady;

  final List<String> _userMessages = [];
  final List<String> _aiMessages = [];
  String _currentUserText = '';
  String _currentAiText = '';
  bool _isSpeaking = false; // 标记用户是否正在说话

  late ScrollController _userScrollController;
  late ScrollController _aiScrollController;

  late AnimationController _opacityController;
  late AnimationController _scaleController;
  late AnimationController _timeController;
  late AnimationController _leftTerminalSlideController;
  late AnimationController _rightTerminalSlideController;

  static const Color _themeColor = Color(0xFFFFB6C1);
  static const Color _terminalBackground = Color(0xFFFFE4E1);

  LinMeimeiPet({required this.vsync, required this.onModelReady}) {
    _userScrollController = ScrollController();
    _aiScrollController = ScrollController();
    _initAnimationControllers();
    onModelReady();
  }

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
    _timeController = AnimationController.unbounded(
      vsync: vsync,
      duration: const Duration(days: 365),
    )..animateTo(const Duration(days: 365).inSeconds.toDouble());
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
  String get name => 'lin-meimei';

  @override
  void handleCommand(String command) {
    if (command == 'wake') {
      _opacityController.forward();
      _scaleController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else if (command == 'reset_scale') {
      // 用户讲完话，恢复特效大小（从 1.1 回到 1）
      if (_scaleController.value > 1.0) {
        _scaleController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (command == 'hide') {
      _opacityController.reverse();
      _scaleController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInCubic,
      );
      _leftTerminalSlideController.reverse();
      _rightTerminalSlideController.reverse();
      _userMessages.clear();
      _aiMessages.clear();
      _currentUserText = '';
      _currentAiText = '';
    } else if (command.startsWith('user:')) {
      final text = command.substring(5);
      if (text.isEmpty) return;
      // 用户讲话，从当前值平滑变到 1.1（只触发一次）
      if (!_isSpeaking) {
        _isSpeaking = true;
        _scaleController.animateTo(
          1.1,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_userScrollController.hasClients) {
          _userScrollController.jumpTo(
            _userScrollController.position.maxScrollExtent,
          );
        }
      });
    } else if (command.startsWith('ai:')) {
      final text = command.substring(3);
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_aiScrollController.hasClients) {
          _aiScrollController.jumpTo(
            _aiScrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  Widget buildEffects(
    BuildContext context,
    double screenWidth,
    double screenHeight,
  ) {
    final orbSize = 300.0;

    return Center(
      child: SizedBox(
        width: orbSize,
        height: orbSize,
        child: AnimatedBuilder(
          animation: _opacityController,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityController.value,
              child: AnimatedBuilder(
                animation: _scaleController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleController.value,
                    child: AnimatedBuilder(
                      animation: _timeController,
                      builder: (context, child) {
                        return OrbRenderer(time: _timeController.value);
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
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
              isUser: false,
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
              isUser: true,
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
    required bool isUser,
  }) {
    final List<Widget> items = [];
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
    if (items.isNotEmpty) {
      items.add(const Divider(color: Colors.white24, height: 16));
    }
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
        border: Border.all(color: _themeColor.withAlpha(150), width: 0),
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

  @override
  void dispose() {
    _userScrollController.dispose();
    _aiScrollController.dispose();
    _opacityController.dispose();
    _scaleController.dispose();
    _timeController.dispose();
    _leftTerminalSlideController.dispose();
    _rightTerminalSlideController.dispose();
  }
}
