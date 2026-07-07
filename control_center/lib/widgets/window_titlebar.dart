import 'dart:io';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 自绘窗口标题栏。
///
/// 平台自适应：
///   - macOS       ：保留系统原生红绿灯（不自绘按钮），左侧留位，仅一条可拖拽品牌条
///   - Windows/Linux：右侧最小化/最大化/关闭线性按钮（bitsdojo 自定义边框）
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
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.accent.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(
          children: [
            // 品牌 + 拖拽区
            Expanded(
              child: MoveWindow(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 1,
                        color: AppColors.accent.withValues(alpha: 0.38),
                      ),
                      const SizedBox(width: 10),
                      const ReactorMark(size: 20, icon: Icons.graphic_eq),
                      const SizedBox(width: 9),
                      const Text(
                        'ASSISTANT CONTROL CENTER',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 70,
                        height: 1,
                        color: AppColors.accent.withValues(alpha: 0.38),
                      ),
                    ],
                  ),
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
