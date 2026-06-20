import 'package:flutter/material.dart';
import '../../tcp_server.dart';
import '../jarvis/jarvis_overlay.dart';
import '../linmeimei/linmeimei_overlay.dart';
import '../xiaonu/xiaonu_overlay.dart';
import 'agent_visual.dart';

/// Agent 特效调度器 — 根据命令切换不同 Agent 的可视化特效
///
/// 新增 Agent 只需：
///   1. 创建新类实现 AgentVisual
///   2. 在 _initAgents 中注册
///   3. 通过 TCP 发送 `agent:xxx` 切换
class AgentOverlay extends StatefulWidget {
  final double screenHeight;

  const AgentOverlay({super.key, required this.screenHeight});

  @override
  State<AgentOverlay> createState() => _AgentOverlayState();
}

class _AgentOverlayState extends State<AgentOverlay>
    with TickerProviderStateMixin {
  final JarvisTCPServer _tcpServer = JarvisTCPServer();
  final Map<String, AgentVisual> _agents = {};
  String _currentAgentName = 'jarvis';
  DateTime? _lastWakeTime;
  static const _wakeCooldownMs = 1500;

  @override
  void initState() {
    super.initState();
    _initAgents();
    _initTCPServer();
  }

  void _initAgents() {
    print('[AgentOverlay] 预加载所有 Agent 模型...');
    _agents['jarvis'] = JarvisAgentVisual(vsync: this);

    _agents['lin-meimei'] = LinMeimeiPet(
      vsync: this,
      onModelReady: () {
        setState(() {});
      },
    );

    _agents['xiao-nu'] = Xiaonupet(vsync: this);

    print('[AgentOverlay] 所有 Agent 初始化完成');
  }

  void _initTCPServer() {
    _tcpServer.onMessage = _handleCommand;
    _tcpServer.start();
  }

  void _handleCommand(String command) {
    print('[AgentOverlay] Received command: $command');

    if (command == 'wake') {
      final now = DateTime.now();
      if (_lastWakeTime != null &&
          now.difference(_lastWakeTime!).inMilliseconds < _wakeCooldownMs) {
        print('[AgentOverlay] Ignoring duplicate wake command');
        return;
      }
      _lastWakeTime = now;
    }

    if (command.startsWith('agent:')) {
      final agentName = command.substring(6).trim();
      print(
        '[AgentOverlay] Agent switch request: $agentName, current: $_currentAgentName',
      );
      if (agentName != _currentAgentName && _agents.containsKey(agentName)) {
        print('[AgentOverlay] Switching to agent: $agentName');
        setState(() {
          _agents[_currentAgentName]!.handleCommand('hide');
          _currentAgentName = agentName;
        });
        print('[AgentOverlay] Switched to Agent: $agentName');
      } else if (!_agents.containsKey(agentName)) {
        print('[AgentOverlay] ERROR: Unknown agent: $agentName');
      } else {
        print('[AgentOverlay] Already on agent: $agentName');
      }
      return;
    }

    print('[AgentOverlay] Dispatching to $_currentAgentName: $command');
    setState(() {
      _agents[_currentAgentName]!.handleCommand(command);
    });
  }

  @override
  void dispose() {
    for (final agent in _agents.values) {
      agent.dispose();
    }
    _tcpServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = widget.screenHeight;

    final agentList = _agents.entries.toList();
    final currentIndex = agentList.indexWhere(
      (e) => e.key == _currentAgentName,
    );

    return IndexedStack(
      index: currentIndex,
      sizing: StackFit.expand,
      children: agentList.map((entry) {
        final agent = entry.value;
        return Stack(
          children: [
            agent.buildAiTerminal(context, screenWidth, screenHeight),
            agent.buildUserTerminal(context, screenWidth, screenHeight),
            agent.buildToolCallTerminal(context, screenWidth, screenHeight),
            agent.buildEffects(context, screenWidth, screenHeight),
          ],
        );
      }).toList(),
    );
  }
}
