import 'dart:io';

class ConfigService {
  String get _projectDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final base =
        '$home/.openclaw/workspace/voice-assistant/assistant-x-openclaw';
    return Platform.isWindows ? base.replaceAll('/', '\\') : base;
  }

  File get _envFile =>
      File(Platform.isWindows ? '$_projectDir\\.env' : '$_projectDir/.env');

  Future<GlobalConfig> load() async {
    final values = await _readValues();
    return GlobalConfig(
      speakerThreshold: _asDouble(
        values['VOICE_ASSISTANT_SPEAKER_THRESHOLD'],
        0.55,
      ),
      livenessEnabled: _asBool(
        values['VOICE_ASSISTANT_LIVENESS_ENABLED'],
        true,
      ),
      livenessEnforce: _asBool(
        values['VOICE_ASSISTANT_LIVENESS_ENFORCE'],
        false,
      ),
      livenessThreshold: _asDouble(
        values['VOICE_ASSISTANT_LIVENESS_THRESHOLD'],
        0.5,
      ),
      mediaWakeGuardEnabled: _asBool(
        values['VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENABLED'],
        true,
      ),
      mediaWakeGuardEnforce: _asBool(
        values['VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENFORCE'],
        false,
      ),
    );
  }

  Future<void> save(GlobalConfig config) async {
    final updates = <String, String>{
      'VOICE_ASSISTANT_SPEAKER_THRESHOLD': _formatDouble(
        config.speakerThreshold,
      ),
      'VOICE_ASSISTANT_LIVENESS_ENABLED': _formatBool(config.livenessEnabled),
      'VOICE_ASSISTANT_LIVENESS_ENFORCE': _formatBool(config.livenessEnforce),
      'VOICE_ASSISTANT_LIVENESS_THRESHOLD': _formatDouble(
        config.livenessThreshold,
      ),
      'VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENABLED': _formatBool(
        config.mediaWakeGuardEnabled,
      ),
      'VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENFORCE': _formatBool(
        config.mediaWakeGuardEnforce,
      ),
    };

    final file = _envFile;
    final original = await file.exists()
        ? await file.readAsLines()
        : <String>[];
    final seen = <String>{};
    final next = <String>[];

    for (final line in original) {
      final match = RegExp(
        r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=',
      ).firstMatch(line);
      if (match == null) {
        next.add(line);
        continue;
      }
      final key = match.group(1)!;
      if (!updates.containsKey(key)) {
        next.add(line);
        continue;
      }
      next.add('$key=${updates[key]}');
      seen.add(key);
    }

    final missing = updates.keys.where((key) => !seen.contains(key)).toList();
    if (missing.isNotEmpty) {
      if (next.isNotEmpty && next.last.trim().isNotEmpty) next.add('');
      next.add('# 声纹与活体检测配置（由 Control Center 写入）');
      for (final key in missing) {
        next.add('$key=${updates[key]}');
      }
    }

    await file.writeAsString('${next.join('\n')}\n');
  }

  Future<Map<String, String>> _readValues() async {
    final file = _envFile;
    if (!await file.exists()) return {};
    final result = <String, String>{};
    for (final raw in await file.readAsLines()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final idx = line.indexOf('=');
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  bool _asBool(String? value, bool fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    return {'1', 'true', 'yes', 'on', 'y'}.contains(value.trim().toLowerCase());
  }

  double _asDouble(String? value, double fallback) {
    if (value == null) return fallback;
    return double.tryParse(value.trim()) ?? fallback;
  }

  String _formatBool(bool value) => value ? 'true' : 'false';

  String _formatDouble(double value) {
    final fixed = value.toStringAsFixed(3);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class GlobalConfig {
  final double speakerThreshold;
  final bool livenessEnabled;
  final bool livenessEnforce;
  final double livenessThreshold;
  final bool mediaWakeGuardEnabled;
  final bool mediaWakeGuardEnforce;

  const GlobalConfig({
    required this.speakerThreshold,
    required this.livenessEnabled,
    required this.livenessEnforce,
    required this.livenessThreshold,
    required this.mediaWakeGuardEnabled,
    required this.mediaWakeGuardEnforce,
  });

  GlobalConfig copyWith({
    double? speakerThreshold,
    bool? livenessEnabled,
    bool? livenessEnforce,
    double? livenessThreshold,
    bool? mediaWakeGuardEnabled,
    bool? mediaWakeGuardEnforce,
  }) {
    return GlobalConfig(
      speakerThreshold: speakerThreshold ?? this.speakerThreshold,
      livenessEnabled: livenessEnabled ?? this.livenessEnabled,
      livenessEnforce: livenessEnforce ?? this.livenessEnforce,
      livenessThreshold: livenessThreshold ?? this.livenessThreshold,
      mediaWakeGuardEnabled:
          mediaWakeGuardEnabled ?? this.mediaWakeGuardEnabled,
      mediaWakeGuardEnforce:
          mediaWakeGuardEnforce ?? this.mediaWakeGuardEnforce,
    );
  }
}
