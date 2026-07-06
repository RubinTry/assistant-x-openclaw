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

  Future<void> _openEditor({ModelEntry? entry, bool clone = false}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ModelEditorDialog(service: _service, entry: entry, clone: clone),
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
        title: const Text('模型路由'),
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
        foregroundColor: const Color(0xFF021018),
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
        _buildInfoBar(models.length),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: models.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) =>
                _buildTile(models[i], models[i].id == current),
          ),
        ),
      ],
    );
  }

  /// 顶部说明条：解释「使用中」的含义。
  Widget _buildInfoBar(int modelCount) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const ReactorMark(size: 34, icon: Icons.memory_outlined),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快路径模型路由',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '使用中的模型负责第一线分流：轻消息直答，重任务通过工具调用升级主脑。',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _miniStat('模型数', '$modelCount'),
          const SizedBox(width: 8),
          _miniStat('校验', '必需'),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.accentSoft,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ModelEntry e, bool isCurrent) {
    return Panel(
      borderColor: isCurrent ? AppColors.accent : AppColors.border,
      borderWidth: isCurrent ? 1.6 : 1,
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
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isCurrent ? AppColors.accent : AppColors.textMuted)
                        .withValues(alpha: 0.1),
                    border: Border.all(
                      color: isCurrent ? AppColors.accent : AppColors.border,
                    ),
                  ),
                  child: Icon(
                    isCurrent ? Icons.check : Icons.circle_outlined,
                    size: 15,
                    color: isCurrent ? AppColors.accent : AppColors.textMuted,
                  ),
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
                    _metaRow(
                      Icons.dns_outlined,
                      '${e.provider.isEmpty ? "—" : e.provider} · ${e.model}',
                    ),
                    const SizedBox(height: 3),
                    _metaRow(Icons.link, e.baseUrl),
                    const SizedBox(height: 3),
                    _metaRow(
                      e.provider.toLowerCase() == 'openai-codex'
                          ? Icons.login
                          : Icons.key_outlined,
                      e.provider.toLowerCase() == 'openai-codex'
                          ? '使用本机 Codex 登录态'
                          : (e.apiKeySet ? e.apiKeyMasked : '未设置'),
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
                    tooltip: '克隆',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    color: AppColors.accent,
                    onPressed: () => _openEditor(entry: e, clone: true),
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

/// OpenAI-compatible provider presets.
///
/// The fast path always validates through the OpenAI Chat Completions shape, so
/// native non-compatible APIs are intentionally represented through compatible
/// gateways such as OpenRouter instead of their native endpoints.
class _ModelPreset {
  final String title;
  final String subtitle;
  final String label;
  final String provider;
  final String baseUrl;
  final String model;
  final IconData icon;

  const _ModelPreset({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.icon,
  });
}

const _modelPresets = [
  _ModelPreset(
    title: 'OpenAI Codex',
    subtitle: 'Codex login',
    label: 'OpenAI Codex',
    provider: 'openai-codex',
    baseUrl: 'codex://local',
    model: 'gpt-5.4-mini',
    icon: Icons.terminal,
  ),
  _ModelPreset(
    title: 'OpenAI',
    subtitle: 'GPT-4.1 mini',
    label: 'OpenAI GPT-4.1 mini',
    provider: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4.1-mini',
    icon: Icons.auto_awesome,
  ),
  _ModelPreset(
    title: 'DeepSeek',
    subtitle: 'deepseek-chat',
    label: 'DeepSeek Chat',
    provider: 'deepseek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    icon: Icons.bolt_outlined,
  ),
  _ModelPreset(
    title: 'Gemini',
    subtitle: 'OpenAI endpoint',
    label: 'Gemini 2.5 Flash',
    provider: 'gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    model: 'gemini-2.5-flash',
    icon: Icons.diamond_outlined,
  ),
  _ModelPreset(
    title: 'Grok',
    subtitle: 'xAI',
    label: 'Grok 3 Mini',
    provider: 'grok',
    baseUrl: 'https://api.x.ai/v1',
    model: 'grok-3-mini',
    icon: Icons.public,
  ),
  _ModelPreset(
    title: 'Anthropic',
    subtitle: 'via OpenRouter',
    label: 'Claude Sonnet (OpenRouter)',
    provider: 'anthropic',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'anthropic/claude-sonnet-4',
    icon: Icons.psychology_alt_outlined,
  ),
  _ModelPreset(
    title: 'OpenRouter',
    subtitle: 'model router',
    label: 'OpenRouter Auto',
    provider: 'openrouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openrouter/auto',
    icon: Icons.hub_outlined,
  ),
  _ModelPreset(
    title: 'Ollama',
    subtitle: 'local',
    label: 'Ollama Local',
    provider: 'ollama',
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'qwen3:latest',
    icon: Icons.memory_outlined,
  ),
  _ModelPreset(
    title: 'LM Studio',
    subtitle: 'local',
    label: 'LM Studio Local',
    provider: 'lmstudio',
    baseUrl: 'http://127.0.0.1:1234/v1',
    model: 'local-model',
    icon: Icons.computer_outlined,
  ),
];

/// 新增/编辑弹窗：填表 → 校验并保存（校验不过不落表）。
class _ModelEditorDialog extends StatefulWidget {
  final ModelService service;
  final ModelEntry? entry;
  final bool clone;
  const _ModelEditorDialog({
    required this.service,
    this.entry,
    this.clone = false,
  });

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

  bool get _isClone => widget.clone && widget.entry != null;
  bool get _isEdit => widget.entry != null && !_isClone;
  bool get _isCodexProvider =>
      _provider.text.trim().toLowerCase() == 'openai-codex';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _label = TextEditingController(
      text: _isClone && e != null ? '${e.label} 副本' : e?.label ?? '',
    );
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
    // 新增必须有 key；克隆/编辑留空表示沿用原 key。
    if (!_isEdit &&
        !_isClone &&
        !_isCodexProvider &&
        _apiKey.text.trim().isEmpty) {
      return '新增模型必须填 API Key';
    }
    return null;
  }

  void _applyPreset(_ModelPreset preset) {
    setState(() {
      _label.text = preset.label;
      _provider.text = preset.provider;
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.model;
      _probe = null;
      _formError = null;
    });
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
      // 编辑/克隆时若未改 key，用原条目的 key 校验当前表单字段。
      final keySourceId =
          (_isEdit || _isClone) &&
              !_isCodexProvider &&
              _apiKey.text.trim().isEmpty
          ? widget.entry!.id
          : null;
      final probe = await widget.service.validate(
        provider: _provider.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: keySourceId != null || _isCodexProvider
            ? null
            : _apiKey.text.trim(),
        apiKeySourceId: keySourceId,
      );
      if (!mounted) return;
      setState(() => _probe = probe);

      if (!probe.ok) {
        setState(() => _busy = false);
        return; // 校验不过：展示原因，不落表
      }

      await widget.service.upsert(
        id: _isEdit ? widget.entry?.id : null,
        label: _label.text.trim().isEmpty
            ? _model.text.trim()
            : _label.text.trim(),
        provider: _provider.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        model: _model.text.trim(),
        apiKey: _isCodexProvider ? null : _apiKey.text.trim(),
        apiKeySourceId:
            _isClone && !_isCodexProvider && _apiKey.text.trim().isEmpty
            ? widget.entry!.id
            : null,
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
          Icon(
            _isClone
                ? Icons.copy_all_outlined
                : (_isEdit ? Icons.edit_outlined : Icons.add),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(_isClone ? '克隆模型' : (_isEdit ? '编辑模型' : '添加模型')),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 640,
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _presetGrid(),
              const SizedBox(height: 8),
              _field(_label, '显示名称', hint: '如 DeepSeek Chat（留空用 model）'),
              _field(
                _provider,
                'Provider',
                hint: '展示用标签，如 deepseek',
                onChanged: (_) => setState(() {
                  _probe = null;
                  _formError = null;
                }),
              ),
              _field(
                _baseUrl,
                'Base URL',
                required: true,
                hint: 'OpenAI 标准，如 https://api.deepseek.com/v1',
              ),
              _field(_model, 'Model', required: true, hint: '如 deepseek-chat'),
              if (_isCodexProvider) _codexAuthNote() else _keyField(),
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

  Widget _presetGrid() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.55),
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune, size: 15, color: AppColors.textMuted),
              SizedBox(width: 7),
              Text(
                'Provider 预设',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _modelPresets) _presetButton(preset),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetButton(_ModelPreset preset) {
    final selected =
        _provider.text.trim() == preset.provider &&
        _baseUrl.text.trim() == preset.baseUrl &&
        _model.text.trim() == preset.model;
    return Tooltip(
      message: '${preset.baseUrl}\n${preset.model}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _busy ? null : () => _applyPreset(preset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : AppColors.surfaceHigh.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.72)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  preset.icon,
                  size: 17,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.title,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.subtitle,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        onChanged: onChanged,
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
          labelText: (_isEdit || _isClone) ? 'API Key' : 'API Key *',
          hintText: _isClone
              ? '留空 = 沿用原 key'
              : (_isEdit ? '留空 = 不修改原 key' : '必填'),
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

  Widget _codexAuthNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: AppShape.borderRadius,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.24)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.login, size: 15, color: AppColors.accent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'OpenAI Codex 使用本机 Codex 登录态，不需要 API Key。若校验失败，请先运行 codex login。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
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
              Icon(
                p.ok ? Icons.verified : Icons.warning_amber_rounded,
                size: 16,
                color: color,
              ),
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
