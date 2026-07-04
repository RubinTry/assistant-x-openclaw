import 'package:flutter/material.dart';

/// Control Center 设计令牌 —— 全局唯一色彩/形状来源。
///
/// 约定：页面代码一律引用这里的令牌，不再散落硬编码色值。
/// 控制台类工具选深色为唯一主题；品牌色沿用 teal 系（与语音助手 HUD 呼应）。
abstract final class AppColors {
  // ── 背景层级（由深到浅）─────────────────────────────
  static const bg = Color(0xFF0E1116); // Scaffold 底
  static const surface = Color(0xFF151A21); // 面板 / 卡片
  static const surfaceHigh = Color(0xFF1C232C); // 面板头部 / hover
  static const border = Color(0xFF262E38); // 描边

  // ── 品牌与语义色 ───────────────────────────────────
  static const accent = Color(0xFF2DD4BF); // teal 品牌色
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);

  // ── 文字层级 ───────────────────────────────────────
  static const textPrimary = Color(0xFFE6EAF0);
  static const textSecondary = Color(0xFF9AA4B2);
  static const textMuted = Color(0xFF626D7A);

  // ── 控制台 ─────────────────────────────────────────
  static const consoleText = Color(0xFFCBD5E1);
  static const consoleSelection = Color(0x553B82F6);
}

abstract final class AppShape {
  static const radius = 10.0;
  static final borderRadius = BorderRadius.circular(radius);
}

/// 全局深色主题。
ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: AppColors.bg,
        primary: AppColors.accent,
        error: AppColors.danger,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF07231F),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.bg,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShape.borderRadius,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShape.borderRadius,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: WidgetStateProperty.all(true),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(const Color(0xFF3A4450)),
      trackColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// 状态胶囊（运行中 / 已停止 等）。
class StatusPill extends StatelessWidget {
  final bool active;
  final String activeText;
  final String inactiveText;

  const StatusPill({
    super.key,
    required this.active,
    this.activeText = '运行中',
    this.inactiveText = '已停止',
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            active ? activeText : inactiveText,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一的面板容器（控制台、卡片列表项等）。
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double borderWidth;

  const Panel({
    super.key,
    required this.child,
    this.margin,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.borderRadius,
        border: Border.all(
          color: borderColor ?? AppColors.border,
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}
