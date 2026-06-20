import 'package:flutter/material.dart';

/// Agent 特效抽象接口
///
/// 所有 Agent 的可视化特效必须实现此接口。
/// 统一标准：
///   1. 用户终端区 — 展示用户说的话
///   2. AI 终端区   — 展示 AI 回复的话
///   3. 其他特效区  — Canvas 动画、桌宠等（由各 Agent 自行实现）
abstract class AgentVisual {
  /// Agent 标识名称
  String get name;

  /// 处理来自 Python 后端的 TCP 命令
  ///
  /// 命令格式：
  ///   - `wake`         — 唤醒特效
  ///   - `hide`         — 隐藏所有特效
  ///   - `user:{text}`  — 用户终端区文本
  ///   - `ai:{text}`    — AI 终端区文本
  ///   - 其他自定义命令   — 由子类自行处理
  void handleCommand(String command);

  /// 构建用户终端区 — 展示用户说的话
  Widget buildUserTerminal(
      BuildContext context, double screenWidth, double screenHeight);

  /// 构建 AI 终端区 — 展示 AI 回复的话
  Widget buildAiTerminal(
      BuildContext context, double screenWidth, double screenHeight);

  /// 构建工具调用终端区 — 展示正在调用的工具（右上角）
  Widget buildToolCallTerminal(
      BuildContext context, double screenWidth, double screenHeight);

  /// 构建特效区 — Canvas 动画、桌宠等各 Agent 自行发挥的区域
  Widget buildEffects(
      BuildContext context, double screenWidth, double screenHeight);


  /// 释放资源
  void dispose();
}
