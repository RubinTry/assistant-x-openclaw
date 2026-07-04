import 'package:flutter/material.dart';
import '../services/model_service.dart';
import '../theme.dart';

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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger.withValues(alpha: 0.16),
              foregroundColor: AppColors.danger,
            ),
            child: const Text('删除'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF07231F),
        icon: const Icon(Icons.add),
        label: const Text('添加模型'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: '无法读取模型表',
        subtitle: _error!,
        action: OutlinedButton(onPressed: _reload, child: const Text('重试')),
      );
    }
    final models = _table?.models ?? [];
    if (models.isEmpty) {
      return const _EmptyState(
        icon: Icons.bolt_outlined,
        title: '还没有配置快路径模型',
        subtitle: '点右下角「添加模型」，须通过工具调用校验才能保存',
      );
    }
    final current = _table?.current;
    return Column(
      children: [
        _buildInfoBar(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: models.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) =>
                _buildTile(models[i], models[i].id == current),
          ),
        ),
      ],
    );
  }

  /// 顶部说明条：解释「使用中」的含义。
  Widget _buildInfoBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '「使用中」的模型作为分流快路径的第一线：轻消息直接回答，重消息经工具调用转交主脑。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ModelEntry e, bool isCurrent) {
    return Panel(
      borderColor: isCurrent ? AppColors.accent : AppColors.border,
      borderWidth: isCurrent ? 1.5 : 1,
      child: InkWell(
        borderRadius: AppShape.borderRadius,
        onTap: isCurrent ? null : () => _setCurrent(e.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 单选指示
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  isCurrent
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isCurrent ? AppColors.accent : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              // 主体信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          _tag('使用中', AppColors.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _metaRow(Icons.dns_outlined,
                        '${e.provider.isEmpty ? "—" : e.provider} · ${e.model}'),
                    const SizedBox(height: 3),
                    _metaRow(Icons.link, e.baseUrl),
                    const SizedBox(height: 3),
                    _metaRow(
                      Icons.key_outlined,
                      e.apiKeySet ? e.apiKeyMasked : '未设置',
                    ),
                  ],
                ),
              ),
              // 操作
              Column(
                children: [
                  IconButton(
                    tooltip: '编辑',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: () => _openEditor(entry: e),
                  ),
                  IconButton(
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppColors.danger,
                    onPressed: () => _delete(e),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 空/错误态占位。
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
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
  bool _obscureKey = true;
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
    if (_baseUrl.text.trim().isEmpty) {
      return 'Base URL 必填（OpenAI 标准，如 https://api.deepseek.com/v1）';
    }
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
        label:
            _label.text.trim().isEmpty ? _model.text.trim() : _label.text.trim(),
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
      title: Row(
        children: [
          Icon(_isEdit ? Icons.edit_outlined : Icons.add, size: 18),
          const SizedBox(width: 8),
          Text(_isEdit ? '编辑模型' : '添加模型'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_label, '显示名称', hint: '如 DeepSeek Chat（留空用 model）'),
              _field(_provider, 'Provider', hint: '展示用标签，如 deepseek'),
              _field(_baseUrl, 'Base URL',
                  required: true,
                  hint: 'OpenAI 标准，如 https://api.deepseek.com/v1'),
              _field(_model, 'Model', required: true, hint: '如 deepseek-chat'),
              _keyField(),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                _banner(_formError!, AppColors.danger, Icons.error_outline),
              ],
              if (_probe != null) ...[
                const SizedBox(height: 12),
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF07231F),
                  ),
                )
              : const Icon(Icons.verified_outlined, size: 18),
          label: Text(_busy ? '校验中…' : '校验并保存'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
        ),
      ),
    );
  }

  Widget _keyField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _apiKey,
        obscureText: _obscureKey,
        decoration: InputDecoration(
          labelText: _isEdit ? 'API Key' : 'API Key *',
          hintText: _isEdit ? '留空 = 不修改原 key' : '必填',
          suffixIcon: IconButton(
            icon: Icon(
              _obscureKey ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _probeReport(ProbeResult p) {
    Widget row(String label, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.cancel,
                size: 15,
                color: ok ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
    final color = p.ok ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(p.ok ? Icons.verified : Icons.warning_amber_rounded,
                  size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                p.ok ? '校验通过' : '校验未通过',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          row('端点可达', p.reachable),
          row('鉴权有效', p.authOk),
          row('模型有效', p.modelOk),
          row('支持工具调用（分流升级必需）', p.toolSupport),
          if (p.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              p.message,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
