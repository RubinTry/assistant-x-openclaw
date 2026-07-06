import 'dart:convert';
import 'dart:io';

/// 模型表读写 —— 直接调 venv Python 子进程（scripts/model_cli.py），
/// **不依赖语音助手是否启动**。
///
/// 模型配置本就是"生成 model_table.json"的独立步骤，助手启动时再读它。
/// 加解密仍在 Python 一侧完成；含明文 key 的入参走子进程 stdin，不进 argv。
///   list                 列表（api_key 掩码）
///   upsert   (stdin JSON) 新增/更新（空 api_key = 保持原值）
///   current  (stdin JSON) 切换 current
///   delete   (stdin JSON) 删除
///   validate (stdin JSON) 能力探针（存表前校验，含工具调用支持）
class ModelService {
  /// 项目根目录（与声纹服务同一约定）。
  String get _projectDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final base =
        '$home/.openclaw/workspace/voice-assistant/assistant-x-openclaw';
    return Platform.isWindows ? base.replaceAll('/', '\\') : base;
  }

  String get _venvPython => Platform.isWindows
      ? '$_projectDir\\venv\\Scripts\\python.exe'
      : '$_projectDir/venv/bin/python';

  String get _cliScript => Platform.isWindows
      ? '$_projectDir\\scripts\\model_cli.py'
      : '$_projectDir/scripts/model_cli.py';

  /// 跑一次 CLI：命令 + 可选 stdin JSON，返回解析后的 stdout JSON。
  Future<Map<String, dynamic>> _run(
    String command, {
    Map<String, dynamic>? payload,
  }) async {
    Process proc;
    try {
      proc = await Process.start(_venvPython, [_cliScript, command]);
    } catch (e) {
      throw ModelServiceException('无法启动模型配置进程（venv/Python 缺失？）：$e');
    }
    if (payload != null) {
      proc.stdin.add(utf8.encode(jsonEncode(payload)));
    }
    await proc.stdin.close();

    final out = await proc.stdout.transform(utf8.decoder).join();
    final err = await proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;

    Map<String, dynamic> data = {};
    if (out.trim().isNotEmpty) {
      try {
        data = (jsonDecode(out) as Map).cast<String, dynamic>();
      } catch (_) {
        throw ModelServiceException('模型配置进程输出异常：${out.trim()}');
      }
    }
    if (code != 0 || data['error'] != null) {
      throw ModelServiceException(
        (data['error'] ?? (err.trim().isNotEmpty ? err.trim() : 'exit $code'))
            .toString(),
      );
    }
    return data;
  }

  /// 列表 + current。models 内 api_key 为掩码串。
  Future<ModelTable> list() async => ModelTable.fromJson(await _run('list'));

  /// 新增/更新。apiKey 传 null 或空 = 更新时保持原 key 不变。
  Future<void> upsert({
    String? id,
    required String label,
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
    String? apiKeySourceId,
  }) async {
    await _run(
      'upsert',
      payload: {
        if (id != null && id.isNotEmpty) 'id': id,
        'label': label,
        'provider': provider,
        'base_url': baseUrl,
        'model': model,
        if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
        if (apiKeySourceId != null && apiKeySourceId.isNotEmpty)
          'api_key_source_id': apiKeySourceId,
      },
    );
  }

  Future<void> setCurrent(String id) => _run('current', payload: {'id': id});

  Future<void> delete(String id) => _run('delete', payload: {'id': id});

  /// 能力探针：新条目传明文，或已存条目传 id（后端解密）。
  Future<ProbeResult> validate({
    String? id,
    String? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? apiKeySourceId,
  }) async {
    final payload = <String, dynamic>{};
    if (id != null && id.isNotEmpty) payload['id'] = id;
    if (provider != null) payload['provider'] = provider;
    if (baseUrl != null) payload['base_url'] = baseUrl;
    if (model != null) payload['model'] = model;
    if (apiKey != null) payload['api_key'] = apiKey;
    if (apiKeySourceId != null && apiKeySourceId.isNotEmpty) {
      payload['api_key_source_id'] = apiKeySourceId;
    }
    final data = await _run('validate', payload: payload);
    return ProbeResult.fromJson(
      (data['result'] as Map).cast<String, dynamic>(),
    );
  }
}

class ModelServiceException implements Exception {
  final String message;
  ModelServiceException(this.message);
  @override
  String toString() => message;
}

class ModelTable {
  final String? current;
  final List<ModelEntry> models;
  ModelTable({this.current, required this.models});

  factory ModelTable.fromJson(Map<String, dynamic> j) => ModelTable(
    current: j['current'] as String?,
    models: ((j['models'] as List?) ?? [])
        .map((e) => ModelEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class ModelEntry {
  final String id;
  final String label;
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKeyMasked;
  final bool apiKeySet;
  ModelEntry({
    required this.id,
    required this.label,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKeyMasked,
    required this.apiKeySet,
  });

  factory ModelEntry.fromJson(Map<String, dynamic> j) => ModelEntry(
    id: (j['id'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
    provider: (j['provider'] ?? '').toString(),
    baseUrl: (j['base_url'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
    apiKeyMasked: (j['api_key'] ?? '').toString(),
    apiKeySet: j['api_key_set'] == true,
  );
}

class ProbeResult {
  final bool ok;
  final bool reachable;
  final bool authOk;
  final bool modelOk;
  final bool toolSupport;
  final String message;
  ProbeResult({
    required this.ok,
    required this.reachable,
    required this.authOk,
    required this.modelOk,
    required this.toolSupport,
    required this.message,
  });

  factory ProbeResult.fromJson(Map<String, dynamic> j) => ProbeResult(
    ok: j['ok'] == true,
    reachable: j['reachable'] == true,
    authOk: j['auth_ok'] == true,
    modelOk: j['model_ok'] == true,
    toolSupport: j['tool_support'] == true,
    message: (j['message'] ?? '').toString(),
  );
}
