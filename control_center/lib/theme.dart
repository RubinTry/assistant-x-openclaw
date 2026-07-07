import 'package:flutter/material.dart';

/// Control Center 设计令牌 —— 全局唯一色彩/形状来源。
///
/// 约定：页面代码一律引用这里的令牌，不再散落硬编码色值。
/// 视觉方向：钢铁侠系蓝黑 HUD。黑色金属做底，弧反应堆蓝做交互主色，
/// 少量琥珀色只用于警告/危险提示。
abstract final class AppColors {
  // ── 背景层级（由深到浅）─────────────────────────────
  static const bg = Color(0xFF05080D); // Scaffold 底
  static const surface = Color(0xFF09111B); // 面板 / 卡片
  static const surfaceHigh = Color(0xFF101B28); // 面板头部 / hover
  static const surfaceGlass = Color(0xCC0D1724); // 玻璃层
  static const border = Color(0xFF1C3448); // 描边
  static const borderBright = Color(0xFF2A6686); // 高亮描边

  // ── 品牌与语义色 ───────────────────────────────────
  static const accent = Color(0xFF38D8FF); // arc reactor blue
  static const accentDeep = Color(0xFF0E79B2);
  static const accentSoft = Color(0xFFB7F4FF);
  static const success = Color(0xFF3CE7B3);
  static const danger = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFB84D);

  // ── 文字层级 ───────────────────────────────────────
  static const textPrimary = Color(0xFFF0F8FF);
  static const textSecondary = Color(0xFFA9BED0);
  static const textMuted = Color(0xFF62798C);

  // ── 控制台 ─────────────────────────────────────────
  static const consoleText = Color(0xFF62E8FF);
  static const consoleTextHot = Color(0xFFB9FAFF);
  static const consoleGlow = Color(0xFF22C7FF);
  static const consoleSelection = Color(0x6638D8FF);
}

abstract final class AppShape {
  static const radius = 8.0;
  static final borderRadius = BorderRadius.circular(radius);
}

abstract final class AppControl {
  static const minButtonHeight = 44.0;
  static const minButtonWidth = 96.0;
  static const iconButtonSize = 40.0;
}

abstract final class AppTextStyles {
  static const consoleLed = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.5,
    letterSpacing: 0,
    color: AppColors.consoleText,
    // shadows: [
    //   Shadow(color: AppColors.consoleTextHot, blurRadius: 1.4),
    //   Shadow(color: AppColors.consoleGlow, blurRadius: 7),
    // ],
  );
}

abstract final class AppGradients {
  static const background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF07111C), Color(0xFF05080D), Color(0xFF020409)],
  );

  static const panel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xEE101C2A), Color(0xEE08101A)],
  );

  static const command = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.accent, Color(0xFF0EA5E9)],
  );
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
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
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
        foregroundColor: const Color(0xFF021018),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        minimumSize: const Size(
          AppControl.minButtonWidth,
          AppControl.minButtonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        iconSize: 19,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF021018),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        minimumSize: const Size(
          AppControl.minButtonWidth,
          AppControl.minButtonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        iconSize: 19,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.borderBright),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        minimumSize: const Size(
          AppControl.minButtonWidth,
          AppControl.minButtonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        iconSize: 19,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        minimumSize: const Size(76, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(
          AppControl.iconButtonSize,
          AppControl.iconButtonSize,
        ),
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: AppShape.borderRadius),
        foregroundColor: AppColors.textSecondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF050B13),
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
      thumbColor: WidgetStateProperty.all(AppColors.borderBright),
      trackColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// 全局 HUD 背景：蓝黑金属渐变 + 极轻网格线。
class HudBackground extends StatelessWidget {
  final Widget child;
  const HudBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.background),
      child: CustomPaint(painter: _HudGridPainter(), child: child),
    );
  }
}

class HudRoute extends StatelessWidget {
  final Widget child;
  const HudRoute({super.key, required this.child});

  static const double titleBarInset = 36;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: HudBackground(child: SizedBox.expand())),
        Padding(
          padding: const EdgeInsets.only(top: titleBarInset),
          child: child,
        ),
      ],
    );
  }
}

class _HudGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fine = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), fine);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fine);
    }

    final rail = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.14)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(0, 58), Offset(size.width, 58), rail);
    canvas.drawLine(
      Offset(size.width - 88, 0),
      Offset(size.width - 132, size.height),
      rail,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ReactorMark extends StatelessWidget {
  final double size;
  final IconData icon;
  const ReactorMark({super.key, this.size = 38, this.icon = Icons.mic});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentSoft.withValues(alpha: 0.55),
              ),
            ),
          ),
          Icon(icon, size: size * 0.42, color: AppColors.accentSoft),
        ],
      ),
    );
  }
}

/// 状态胶囊（运行中 / 已停止 等）。
class StatusPill extends StatelessWidget {
  final bool active;
  final String activeText;
  final String inactiveText;
  final bool compact;

  const StatusPill({
    super.key,
    required this.active,
    this.activeText = '运行中',
    this.inactiveText = '已停止',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textMuted;
    final dotSize = compact ? 6.0 : 7.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: compact ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: compact ? 0.26 : 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: compact ? 5 : 6),
          Text(
            active ? activeText : inactiveText,
            style: TextStyle(
              color: color,
              fontSize: compact ? 10.5 : 12,
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
        gradient: AppGradients.panel,
        borderRadius: AppShape.borderRadius,
        border: Border.all(
          color: borderColor ?? AppColors.border,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}
