import 'dart:io';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 自绘窗口标题栏（配合 bitsdojo BDW_CUSTOM_FRAME 隐藏系统原生标题栏）。
///
/// 平台自适应：
///   - macOS       ：左侧红/黄/绿"红绿灯"，悬停显示图标，符合系统习惯
///   - Windows/Linux：右侧最小化/最大化/关闭线性按钮
/// 中间为可拖拽区（双击最大化/还原），承载品牌标题。
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return SizedBox(
      height: height,
      child: Container(
        color: AppColors.bg,
        child: Row(
          children: [
            if (isMac) ...[
              const SizedBox(width: 12),
              const _TrafficLights(),
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: 12),
            // 品牌 + 拖拽区
            Expanded(
              child: MoveWindow(
                child: Row(
                  children: [
                    if (!isMac) ...[
                      const Icon(Icons.mic, size: 14, color: AppColors.accent),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '语音助手控制中心',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isMac) const _WindowButtons(),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// macOS 风格红绿灯（左侧）。
class _TrafficLights extends StatefulWidget {
  const _TrafficLights();

  @override
  State<_TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<_TrafficLights> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        children: [
          _light(
            const Color(0xFFFF5F57),
            Icons.close,
            () => appWindow.close(),
          ),
          const SizedBox(width: 8),
          _light(
            const Color(0xFFFEBC2E),
            Icons.remove,
            () => appWindow.minimize(),
          ),
          const SizedBox(width: 8),
          _light(
            const Color(0xFF28C840),
            Icons.fullscreen,
            () => appWindow.maximizeOrRestore(),
          ),
        ],
      ),
    );
  }

  Widget _light(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: _hovering
            ? Icon(icon, size: 9, color: Colors.black.withValues(alpha: 0.55))
            : null,
      ),
    );
  }
}

/// Windows/Linux 风格窗口按钮（右侧）。
class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    final colors = WindowButtonColors(
      iconNormal: AppColors.textSecondary,
      iconMouseOver: AppColors.textPrimary,
      iconMouseDown: AppColors.textPrimary,
      mouseOver: AppColors.surfaceHigh,
      mouseDown: AppColors.border,
    );
    final closeColors = WindowButtonColors(
      iconNormal: AppColors.textSecondary,
      iconMouseOver: Colors.white,
      iconMouseDown: Colors.white,
      mouseOver: AppColors.danger,
      mouseDown: const Color(0xFFB91C1C),
    );
    return Row(
      children: [
        MinimizeWindowButton(colors: colors, animate: true),
        MaximizeWindowButton(colors: colors, animate: true),
        CloseWindowButton(colors: closeColors, animate: true),
      ],
    );
  }
}
