import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../theme.dart';

class GlobalConfigPage extends StatefulWidget {
  const GlobalConfigPage({super.key});

  @override
  State<GlobalConfigPage> createState() => _GlobalConfigPageState();
}

class _GlobalConfigPageState extends State<GlobalConfigPage> {
  final _service = ConfigService();
  GlobalConfig? _config;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _service.load();
      if (!mounted) return;
      setState(() {
        _config = config;
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

  Future<void> _save() async {
    final config = _config;
    if (config == null) return;
    setState(() => _saving = true);
    try {
      await _service.save(config);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('全局配置已写入 .env，重启语音助手后生效')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _update(GlobalConfig config) {
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全局配置'),
        actions: [
          IconButton(
            tooltip: '重新读取',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: FilledButton.icon(
          onPressed: _loading || _saving || _config == null ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? '保存中' : '保存配置'),
        ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final config = _config!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _intro(),
        const SizedBox(height: 14),
        _section(
          icon: Icons.graphic_eq,
          title: '声纹验证',
          subtitle: '控制已注册声纹匹配的严格程度。',
          children: [
            _thresholdSlider(
              label: '声纹阈值',
              value: config.speakerThreshold,
              min: 0.3,
              max: 0.95,
              onChanged: (value) =>
                  _update(config.copyWith(speakerThreshold: value)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          icon: Icons.verified_user_outlined,
          title: '活体检测',
          subtitle: 'AASIST 被动检测录音、合成或重放音频。',
          children: [
            _switchTile(
              title: '启用活体检测',
              subtitle: '关闭后不再计算活体分数。',
              value: config.livenessEnabled,
              onChanged: (value) =>
                  _update(config.copyWith(livenessEnabled: value)),
            ),
            _switchTile(
              title: '强制拦截活体失败',
              subtitle: '关闭时仅记录 shadow 分数；开启后失败会拒绝唤醒。',
              value: config.livenessEnforce,
              onChanged: (value) =>
                  _update(config.copyWith(livenessEnforce: value)),
            ),
            _thresholdSlider(
              label: '活体阈值',
              value: config.livenessThreshold,
              min: 0.1,
              max: 0.95,
              onChanged: (value) =>
                  _update(config.copyWith(livenessThreshold: value)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          icon: Icons.surround_sound_outlined,
          title: '本机重放防护',
          subtitle: '唤醒瞬间检测电脑是否正在播放媒体。',
          children: [
            _switchTile(
              title: '启用媒体播放门禁',
              subtitle: '用于识别电脑本机正在播放录音触发唤醒。',
              value: config.mediaWakeGuardEnabled,
              onChanged: (value) =>
                  _update(config.copyWith(mediaWakeGuardEnabled: value)),
            ),
            _switchTile(
              title: '强制拦截本机媒体唤醒',
              subtitle: '开启后，电脑正在播放媒体时的唤醒会被拒绝。',
              value: config.mediaWakeGuardEnforce,
              onChanged: (value) =>
                  _update(config.copyWith(mediaWakeGuardEnforce: value)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: AppShape.borderRadius,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.26)),
      ),
      child: const Row(
        children: [
          ReactorMark(size: 34, icon: Icons.tune),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '配置会写入项目根目录 .env；运行中的语音助手需要重启后读取新值。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      value: value,
      activeThumbColor: AppColors.accent,
      activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
      onChanged: onChanged,
    );
  }

  Widget _thresholdSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final clamped = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              clamped.toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: ((max - min) * 100).round(),
          activeColor: AppColors.accent,
          inactiveColor: AppColors.borderBright.withValues(alpha: 0.4),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
