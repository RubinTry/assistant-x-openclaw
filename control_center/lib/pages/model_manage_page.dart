import 'package:flutter/material.dart';
import '../services/model_service.dart';

/// 快路径模型管理页。
///
/// 模型表存在 Python 后端（加密落盘）；本页只经 18790 端点读写明文。
/// 关键约束：**保存前必须通过能力探针**——不支持工具调用的模型会被拦下
/// （分流升级路径靠原生 tool call handoff 给 agent）。
class ModelManagePage extends StatefulWidget {
  const ModelManagePage({super.key});

  @override
  State<ModelManagePage> createState() => _ModelManagePageState();
}

class _ModelManagePageState extends State<ModelManagePage> {
  final ModelService _service = ModelService();
  ModelTable? _table;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _service.list();
      if (!mounted) return;
      setState(() {
        _table = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setCurrent(String id) async {
    try {
      await _service.setCurrent(id);
      await _reload();
    } catch (e) {
      _snack('切换失败：$e');
    }
  }

  Future<void> _delete(ModelEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除模型「${entry.label}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(entry.id);
      await _reload();
    } catch (e) {
      _snack('删除失败：$e');
    }
  }

  Future<void> _openEditor({ModelEntry? entry}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModelEditorDialog(service: _service, entry: entry),
    );
    if (saved == true) await _reload();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快路径模型'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加模型'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    final models = _table?.models ?? [];
    if (models.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('还没有配置快路径模型',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('点右下角「添加模型」，须通过工具调用校验',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      );
    }
    final current = _table?.current;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: models.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildTile(models[i], models[i].id == current),
    );
  }

  Widget _buildTile(ModelEntry e, bool isCurrent) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? Colors.teal : Colors.grey.shade800,
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      child: ListTile(
        leading: Radio<bool>(
          value: true,
          groupValue: isCurrent ? true : null,
          onChanged: isCurrent ? null : (_) => _setCurrent(e.id),
          toggleable: false,
        ),
        title: Row(
          children: [
            Flexible(
                child: Text(e.label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('使用中',
                    style: TextStyle(color: Colors.teal, fontSize: 11)),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.provider.isEmpty ? "-" : e.provider} · ${e.model}',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              Text(e.baseUrl,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              Text('key ${e.apiKeySet ? e.apiKeyMasked : "未设置"}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _openEditor(entry: e),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: () => _delete(e),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新增/编辑弹窗：填表 → 校验并保存（校验不过不落表）。
class _ModelEditorDialog extends StatefulWidget {
  final ModelService service;
  final ModelEntry? entry;
  const _ModelEditorDialog({required this.service, this.entry});

  @override
  State<_ModelEditorDialog> createState() => _ModelEditorDialogState();
}

class _ModelEditorDialogState extends State<_ModelEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _provider;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  bool _busy = false;
  ProbeResult? _probe;
  String? _formError;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _label = TextEditingController(text: e?.label ?? '');
    _provider = TextEditingController(text: e?.provider ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _apiKey = TextEditingController();
  }

  @override
  void dispose() {
    _label.dispose();
    _provider.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_baseUrl.text.trim().isEmpty) return 'Base URL 必填（OpenAI 标准，如 https://api.deepseek.com/v1）';
    if (_model.text.trim().isEmpty) return 'Model 必填';
    // 新增必须有 key；编辑留空表示保持原 key
    if (!_isEdit && _apiKey.text.trim().isEmpty) return '新增模型必须填 API Key';
    return null;
  }

  /// 校验并保存：先探针（能力/工具支持），过了才落表。
  Future<void> _saveWithValidation() async {
    final formErr = _validateForm();
    if (formErr != null) {
      setState(() => _formError = formErr);
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
      _probe = null;
    });

    try {
      // 编辑时若未改 key，用已存条目 id 让后端解密后校验；否则用明文校验。
      final useExistingKey = _isEdit && _apiKey.text.trim().isEmpty;
      final probe = await widget.service.validate(
        id: useExistingKey ? widget.entry!.id : null,
        baseUrl: useExistingKey ? null : _baseUrl.text.trim(),
        model: useExistingKey ? null : _model.text.trim(),
        apiKey: useExistingKey ? null : _apiKey.text.trim(),
      );
      if (!mounted) return;
      setState(() => _probe = probe);

      if (!probe.ok) {
        setState(() => _busy = false);
        return; // 校验不过：展示原因，不落表
      }

      await widget.service.upsert(
        id: widget.entry?.id,
        label: _label.text.trim().isEmpty ? _model.text.trim() : _label.text.trim(),
        provider: _provider.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: _apiKey.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑模型' : '添加模型'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_label, '显示名称', hint: '如 DeepSeek Chat（留空用 model）'),
              _field(_provider, 'Provider', hint: '展示用标签，如 deepseek'),
              _field(_baseUrl, 'Base URL *',
                  hint: 'OpenAI 标准，如 https://api.deepseek.com/v1'),
              _field(_model, 'Model *', hint: '如 deepseek-chat'),
              _field(_apiKey, 'API Key',
                  hint: _isEdit ? '留空 = 不修改原 key' : '必填',
                  obscure: true),
              if (_formError != null) ...[
                const SizedBox(height: 10),
                _banner(_formError!, Colors.red),
              ],
              if (_probe != null) ...[
                const SizedBox(height: 10),
                _probeReport(_probe!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _saveWithValidation,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.verified),
          label: Text(_busy ? '校验中…' : '校验并保存'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _probeReport(ProbeResult p) {
    Widget row(String label, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.cancel,
                  size: 16, color: ok ? Colors.teal : Colors.red),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
    final color = p.ok ? Colors.teal : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.ok ? '校验通过 ✓' : '校验未通过',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          row('端点可达', p.reachable),
          row('鉴权有效', p.authOk),
          row('模型有效', p.modelOk),
          row('支持工具调用（分流升级必需）', p.toolSupport),
          if (p.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.message,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
