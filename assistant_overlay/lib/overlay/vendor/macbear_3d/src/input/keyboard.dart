import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Keyboard system for M3 engine.
/// Avoids Flutter HardwareKeyboard bug and supports key repeat.
class M3KeyboardManager {
  /// All pressed physical keys
  final Set<PhysicalKeyboardKey> _pressed = {};

  /// Repeat tuning
  Duration repeatDelay = const Duration(milliseconds: 380);
  Duration repeatInterval = const Duration(milliseconds: 45);

  /// Timers for key repeat
  final Map<PhysicalKeyboardKey, Timer> _repeatTimers = {};

  /// Mapping for easy access (WASD, arrows…)
  final Map<LogicalKeyboardKey, String> keyMap = {};

  bool _started = false;

  /// ===========================
  /// PUBLIC API
  /// ===========================

  /// Must be called once
  void start() {
    if (_started) return;
    _started = true;

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    _initDefaultMap();
  }

  /// Must call before app exit
  void stop() {
    if (!_started) return;
    _started = false;

    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _clearTimers();
    _pressed.clear();
  }

  /// Check if a logical key is currently pressed
  bool isPressed(LogicalKeyboardKey key) {
    if (_isTextFieldFocused()) return false;
    return HardwareKeyboard.instance.logicalKeysPressed.contains(key);
  }

  /// Get mapped action (W, A, S, D etc.)
  String? getActionByKey(LogicalKeyboardKey key) {
    return keyMap[key];
  }

  /// ===========================
  /// CALLBACKS (your engine can assign handlers)
  /// ===========================
  void Function(KeyDownEvent event)? onKeyDown;
  void Function(KeyUpEvent event)? onKeyUp;
  void Function(PhysicalKeyboardKey key)? onKeyRepeat;
  void Function(String action)? onActionDown;
  void Function(String action)? onActionUp;

  /// ===========================
  /// INTERNAL
  /// ===========================

  bool _isTextFieldFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final context = primaryFocus.context!;
      return context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null;
    }
    return false;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_isTextFieldFocused()) {
      return false;
    }

    final physical = event.physicalKey;
    final logical = event.logicalKey;

    // IME 中文輸入、組字階段不處理
    if (event.character != null &&
        event.character!.isNotEmpty &&
        event.character != '\u0008' && // backspace
        logical == LogicalKeyboardKey.home) {
      return false;
    }

    if (event is KeyDownEvent) {
      // Avoid Flutter key bug: repeated KeyDown without KeyUp
      if (_pressed.contains(physical)) {
        return false;
      }

      _pressed.add(physical);

      // Key repeat system
      _startRepeat(physical);

      onKeyDown?.call(event);

      // Action 單鍵動作 (例：WASD)
      final action = keyMap[logical];
      if (action != null) {
        onActionDown?.call(action);
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(physical);
      _stopRepeat(physical);

      onKeyUp?.call(event);

      final action = keyMap[logical];
      if (action != null) {
        onActionUp?.call(action);
      }
    }

    return false;
  }

  /// ===========================
  /// KEY REPEAT
  /// ===========================
  void _startRepeat(PhysicalKeyboardKey key) {
    if (_repeatTimers.containsKey(key)) return;

    _repeatTimers[key] = Timer(repeatDelay, () {
      _repeatTimers[key] = Timer.periodic(repeatInterval, (timer) {
        if (!_pressed.contains(key)) {
          timer.cancel();
          _repeatTimers.remove(key);
          return;
        }
        onKeyRepeat?.call(key);
      });
    });
  }

  void _stopRepeat(PhysicalKeyboardKey key) {
    _repeatTimers[key]?.cancel();
    _repeatTimers.remove(key);
  }

  void _clearTimers() {
    for (var timer in _repeatTimers.values) {
      timer.cancel();
    }
    _repeatTimers.clear();
  }

  /// ===========================
  /// DEFAULT ACTION MAP
  /// ===========================
  void _initDefaultMap() {
    keyMap.clear();

    keyMap[LogicalKeyboardKey.keyW] = "up";
    keyMap[LogicalKeyboardKey.keyS] = "down";
    keyMap[LogicalKeyboardKey.keyA] = "left";
    keyMap[LogicalKeyboardKey.keyD] = "right";

    keyMap[LogicalKeyboardKey.arrowUp] = "up";
    keyMap[LogicalKeyboardKey.arrowDown] = "down";
    keyMap[LogicalKeyboardKey.arrowLeft] = "left";
    keyMap[LogicalKeyboardKey.arrowRight] = "right";

    keyMap[LogicalKeyboardKey.space] = "jump";
  }
}
