import 'package:flutter/material.dart';

/// JARVIS HUD 终端壳：标题头 + 四角亮角光外框 + 内容布局。
///
/// 抽离自 `jarvis_overlay.dart` 的重复结构（958-974 行 + 929-956 行）。
///
/// 使用场景：
///   - AI 终端（`buildAiTerminal`，左上次顶）
///   - User 终端（`buildUserTerminal`，右下）
///   - System Status 面板（`buildOtherTwo`，左下）
///
/// 与原内联实现严格一致的细节：
///   - 圆角 16、alpha 55 全圈边框、四角亮光（glow alpha=170 blur=6 + crisp 实线）
///   - 内边距 `EdgeInsets.fromLTRB(16, 13, 16, 13)`
///   - 标题色 `0xFF6EB9FF`、字号 12、字距 2、w500
///   - 标题下 9px gap + 1px 分隔线（color.withAlpha(40)）+ 10px gap
///
/// 布局策略：内部 Column 用 `mainAxisSize: min` 让整个 shell 按内容自然撑高，
/// `child` 走 `Flexible(fit: FlexFit.loose)` —— 既给 child 留所有剩余高度空间
/// （shell 父容器有限高时它会收住），又允许内容不足时 shell 自然缩小
/// （避免上一版的 RenderFlex assertion）。
class HudTerminalShell extends StatelessWidget {
  /// 标题文本（如 'J.A.R.V.I.S.'、'MESSAGE FEED'、'SYSTEM STATUS'）。
  final String title;

  /// 固定宽度。
  final double width;

  /// 最大高度（外层约束；`double.infinity` 表示不限）。
  final double maxHeight;

  /// 标题旁的图标。若为 null 则用 `Icons.diamond_outlined`（SYSTEM STATUS 风格）。
  final Widget? titleIcon;

  /// 是否在标题右侧显示状态指示点（点 + color glow）。
  /// 仅消息类终端显示，SYSTEM STATUS 不显示。
  final bool showStatusDot;

  /// 内容区域。期望自带滚动/截断（如 `ListView(shrinkWrap: true)` 或有限高度的 Column）。
  final Widget child;

  const HudTerminalShell({
    super.key,
    required this.title,
    required this.width,
    required this.maxHeight,
    required this.child,
    this.titleIcon,
    this.showStatusDot = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0xFF8CC1FA);
    Color titleColor = const Color(0xFF6EB9FF);
    Color background = const Color(0x330D67BC);
    return CustomPaint(
      foregroundPainter: _TerminalFramePainter(color: color),
      // 不在这里加 BoxConstraints(maxHeight: ...) —— 父级（Positioned +
      // SizedBox）已经限了高。重复限制会让 Column 在子总高 < maxHeight 时被
      // 强行拉到 maxHeight，再叠加 padding 后导致子内容溢出 ~63px。
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            HudTerminalHeader(
              title: title,
              icon: titleIcon,
              showStatusDot: showStatusDot,
              color: color,
              titleColor: titleColor,
            ),
            const SizedBox(height: 9),
            Container(height: 1, color: color.withAlpha(40)),
            const SizedBox(height: 10),
            // Flexible(loose)：给 child 留所有剩余高度但不强占，shell 自然缩。
            Flexible(fit: FlexFit.loose, child: child),
          ],
        ),
      ),
    );
  }
}

/// 标题行：图标 + 标题 +（可选）状态指示点。
///
/// 字号 12 / 字距 2 / 颜色 `0xFF6EB9FF`；与 [HudTerminalShell] 解耦，
/// 可独立用于其他 HUD 场景（不依赖外框 painter）。
class HudTerminalHeader extends StatelessWidget {
  final String title;
  final Widget? icon;
  final bool showStatusDot;
  final Color color;
  final Color titleColor;

  const HudTerminalHeader({
    super.key,
    required this.title,
    required this.color,
    this.titleColor = const Color(0xFF6EB9FF),
    this.icon,
    this.showStatusDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon ??
            const Icon(
              Icons.diamond_outlined,
              size: 14,
              color: Color(0xFF6EB9FF),
            ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
        if (showStatusDot) ...[
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withAlpha(180), blurRadius: 6),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 终端框 HUD 边框：整圈暗淡描边 + 四角更亮的「角光」
/// （含圆角弧，发光层 + 实线层）。保持与 jarvis_overlay.dart 内原实现 1:1 一致。
///
/// 圆角 16、角长 20 写死为常量 — 这两个值历史上从未在调用点被覆盖，
/// 且 HUD 风格全局一致。
class _TerminalFramePainter extends CustomPainter {
  final Color color;

  _TerminalFramePainter({required this.color});

  static const double _radius = 16;
  static const double _cornerLen = 20;

  @override
  void paint(Canvas canvas, Size size) {
    const r = _radius;
    final l = 0.5, t = 0.5;
    final rt = size.width - 0.5, bt = size.height - 0.5;

    // 1) 整圈暗淡边框
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(l, t, rt, bt),
      Radius.circular(r),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withAlpha(55),
    );

    // 2) 四角亮角光：先画一层模糊发光，再压一条清晰亮线
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color.withAlpha(170)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);
    final crisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    for (final p in [glow, crisp]) {
      _corner(canvas, 0, l, t, rt, bt, r, _cornerLen, p); // 左上
      _corner(canvas, 1, l, t, rt, bt, r, _cornerLen, p); // 右上
      _corner(canvas, 2, l, t, rt, bt, r, _cornerLen, p); // 右下
      _corner(canvas, 3, l, t, rt, bt, r, _cornerLen, p); // 左下
    }
  }

  // q: 0=左上 1=右上 2=右下 3=左下。圆角弧用 drawArc（角度无歧义）+ 两条切边直线。
  // 直接用 double 字面量避免再 import dart:math。
  void _corner(
    Canvas c,
    int q,
    double l,
    double t,
    double rt,
    double bt,
    double r,
    double len,
    Paint p,
  ) {
    final d = 2 * r;
    const hp = 1.5707963267948966; // pi/2
    switch (q) {
      case 0:
        c.drawArc(Rect.fromLTWH(l, t, d, d), 3.141592653589793, hp, false, p);
        c.drawLine(Offset(l, t + r), Offset(l, t + r + len), p);
        c.drawLine(Offset(l + r, t), Offset(l + r + len, t), p);
        break;
      case 1:
        c.drawArc(
            Rect.fromLTWH(rt - d, t, d, d), 4.71238898038469, hp, false, p);
        c.drawLine(Offset(rt, t + r), Offset(rt, t + r + len), p);
        c.drawLine(Offset(rt - r, t), Offset(rt - r - len, t), p);
        break;
      case 2:
        c.drawArc(Rect.fromLTWH(rt - d, bt - d, d, d), 0, hp, false, p);
        c.drawLine(Offset(rt, bt - r), Offset(rt, bt - r - len), p);
        c.drawLine(Offset(rt - r, bt), Offset(rt - r - len, bt), p);
        break;
      case 3:
        c.drawArc(Rect.fromLTWH(l, bt - d, d, d), hp, hp, false, p);
        c.drawLine(Offset(l, bt - r), Offset(l, bt - r - len), p);
        c.drawLine(Offset(l + r, bt), Offset(l + r + len, bt), p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TerminalFramePainter old) =>
      old.color != color;
}
