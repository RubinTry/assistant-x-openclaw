import 'dart:convert';
import 'dart:io';

/// 与 Python 后端 18790 的模型表端点通信。
///
/// 后端独占加解密：这里只传明文（本地回环），不做任何加密。
///   GET  /models          列表（api_key 掩码）
///   POST /models          新增/更新（空 api_key = 保持原值）
///   POST /models/current  切换 current
///   POST /models/delete   删除
///   POST /models/validate 能力探针（存表前校验，含工具调用支持）
class ModelService {
  static const String _base = 'http://127.0.0.1:18790';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_base$path');
      final req = method == 'GET'
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      if (body != null) {
        req.add(utf8.encode(jsonEncode(body)));
      }
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decoder.bind(resp).join();
      final data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (resp.statusCode != 200) {
        final err = (data is Map && data['error'] != null)
            ? data['error'].toString()
            : 'HTTP ${resp.statusCode}';
        throw ModelServiceException(err);
      }
      return (data as Map).cast<String, dynamic>();
    } on ModelServiceException {
      rethrow;
    } catch (e) {
      throw ModelServiceException('无法连接语音助手后端（18790）：$e');
    } finally {
      client.close();
    }
  }

  /// 列表 + current。models 内 api_key 为掩码串。
  Future<ModelTable> list() async {
    final data = await _request('GET', '/models');
    return ModelTable.fromJson(data);
  }

  /// 新增/更新。apiKey 传 null 或空 = 更新时保持原 key 不变。
  Future<void> upsert({
    String? id,
    required String label,
    required String provider,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    await _request('POST', '/models', body: {
      if (id != null && id.isNotEmpty) 'id': id,
      'label': label,
      'provider': provider,
      'base_url': baseUrl,
      'model': model,
      if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
    });
  }

  Future<void> setCurrent(String id) =>
      _request('POST', '/models/current', body: {'id': id});

  Future<void> delete(String id) =>
      _request('POST', '/models/delete', body: {'id': id});

  /// 能力探针：新条目传明文，或已存条目传 id（后端解密）。
  Future<ProbeResult> validate({
    String? id,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) async {
    final data = await _request('POST', '/models/validate', body: {
      if (id != null && id.isNotEmpty) 'id': id,
      if (baseUrl != null) 'base_url': baseUrl,
      if (model != null) 'model': model,
      if (apiKey != null) 'api_key': apiKey,
    });
    return ProbeResult.fromJson((data['result'] as Map).cast<String, dynamic>());
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
