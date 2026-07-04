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
  // macOS 原生红绿灯占据左上角，品牌条左侧需让位
  static const double _macTrafficLightInset = 78;

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return SizedBox(
      height: height,
      child: Container(
        color: AppColors.bg,
        child: Row(
          children: [
            SizedBox(width: isMac ? _macTrafficLightInset : 12),
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
