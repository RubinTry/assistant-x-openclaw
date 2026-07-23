import 'package:flutter/foundation.dart';

abstract class M3Log {
  M3Log._();

  static const String _reset = '\x1B[0m';
  static const String _bold = '\x1B[1m';

  // ANSI 顏色代碼
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _cyan = '\x1B[36m';
  static const String _green = '\x1B[32m';
  static const String _white = '\x1B[37m'; // System (Bright)

  // 高亮背景 (例如：黃底黑字)
  static const String _highlight = '\x1B[43m\x1B[30m';

  // 核心私有 log 方法
  static void _print(String tag, Object msg, String color) {
    if (kDebugMode) {
      debugPrint('$color[$tag] $msg$_reset');
    }
  }

  /// info log
  static void i(String tag, Object msg) => _print(tag, msg, _green);

  /// debug log
  static void d(String tag, Object msg) => _print(tag, msg, _cyan);

  /// warning log
  static void w(String tag, Object msg) => _print(tag, msg, _yellow);

  /// error log
  static void e(String tag, Object msg) => _print(tag, msg, '$_bold$_red'); // 粗體紅

  /// system log
  static void s(String tag, Object msg) => _print(tag, msg, _white);

  /// highlight log
  static void h(String tag, Object msg) => _print(tag, msg, _highlight);
}
