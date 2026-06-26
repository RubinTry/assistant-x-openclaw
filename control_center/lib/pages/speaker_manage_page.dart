import 'package:flutter/material.dart';
import '../services/service_factory.dart';

class SpeakerManagePage extends StatefulWidget {
  final void Function(String)? onLog;

  const SpeakerManagePage({super.key, this.onLog});

  @override
  State<SpeakerManagePage> createState() => _SpeakerManagePageState();
}

class _SpeakerManagePageState extends State<SpeakerManagePage> {
  final _service = ServiceFactory.speakerService;
  final _speakers = <String>[];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSpeakers();
  }

  Future<void> _loadSpeakers() async {
    setState(() => _isLoading = true);
    final list = await _service.loadSpeakers();
    setState(() {
      _speakers.clear();
      _speakers.addAll(list);
      _isLoading = false;
    });
  }

  Future<void> _enrollSpeaker() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EnrollDialog(onLog: widget.onLog),
    );

    await _loadSpeakers();

    if (success != true && mounted) {
      final speakers = await _service.loadSpeakers();
      if (speakers.isEmpty && mounted) {
        final enroll = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未检测到声纹样本'),
            content: const Text('是否现在去注册声纹样本？注册后可以用声纹验证来唤醒语音助手。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后再说'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去注册'),
              ),
            ],
          ),
        );
        if (enroll == true && mounted) {
          _enrollSpeaker();
        }
      }
    }
  }

  Future<void> _deleteSpeaker(int index) async {
    final name = _speakers[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 "$name" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteSpeaker(name);
      await _loadSpeakers();
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定清空所有声纹吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _service.clearAllSpeakers();
        await _loadSpeakers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清空所有声纹')),
          );
        }
      } catch (e) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('清空失败'),
              content: SizedBox(
                width: 500,
                height: 200,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      e.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFE0E0E0),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('我知道了'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('声纹管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSpeakers,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _speakers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        '暂无已注册的声纹样本',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _speakers.length,
                  itemBuilder: (ctx, i) {
                    final speaker = _speakers[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(speaker),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteSpeaker(i),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _enrollSpeaker,
              icon: const Icon(Icons.add),
              label: const Text('声纹注册'),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _speakers.isEmpty ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('清空全部'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrollDialog extends StatefulWidget {
  final void Function(String)? onLog;

  const _EnrollDialog({this.onLog});

  @override
  State<_EnrollDialog> createState() => _EnrollDialogState();
}

class _EnrollDialogState extends State<_EnrollDialog> {
  final _logs = <String>[];
  final _scrollController = ScrollController();
  bool _isRunning = true;
  bool _success = false;
  final _service = ServiceFactory.speakerService;
  final _vaService = ServiceFactory.voiceAssistantService;

  @override
  void initState() {
    super.initState();
    _startEnroll();
  }

  @override
  void dispose() {
    // 兜底：弹窗被中途关闭（录入未走到 finally）时也要解除勿扰，避免主程序永久哑火
    _vaService.setDndMode(false);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startEnroll() async {
    // 录入期间进入勿扰：暂停主程序唤醒词响应，避免录音时反复喊"贾维斯"误唤醒。
    // 若主程序 18790 接口没监听（端口被占、进程未起等），勿扰请求会静默失败——
    // 必须显式提示出来，否则用户会以为是声纹逻辑本身的 bug。
    final dndOk = await _vaService.setDndMode(true);
    if (!dndOk) {
      const msg = '[警告] 未能联系主程序开启勿扰模式（18790 端口无响应），'
          '念出唤醒词可能会误唤醒助手，建议重启语音助手后再试';
      widget.onLog?.call(msg);
      if (mounted) setState(() => _logs.add(msg));
    }
    try {
      await for (final msg in _service.enrollSpeakerStream()) {
        widget.onLog?.call(msg);
        if (mounted) {
          setState(() {
            _logs.add(msg);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } finally {
      await _vaService.setDndMode(false);
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
      });
      final speakers = await _service.loadSpeakers();
      if (mounted) {
        setState(() {
          _success = speakers.isNotEmpty;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          if (_isRunning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_isRunning) const SizedBox(width: 8),
          Text(_isRunning ? '声纹录入中...' : (_success ? '录入成功' : '录入失败')),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 300,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: _logs.isEmpty
                    ? Center(
                        child: Text(
                          _isRunning ? '等待录入输出...' : '无输出',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _logs.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFE0E0E0),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRunning ? null : () => Navigator.pop(context, _success),
          child: const Text('我知道了'),
        ),
      ],
    );
  }
}