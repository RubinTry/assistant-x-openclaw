import 'dart:convert';
import 'dart:io';
import '../base/speaker_service_base.dart';

class WindowsSpeakerService implements SpeakerServiceBase {
  String get _expandedPath {
    final home = Platform.environment['USERPROFILE'] ?? 
                 Platform.environment['HOME'] ?? 
                 'C:\\Users\\${Platform.environment['USERNAME']}';
    return '$home\\.openclaw\\workspace\\voice-assistant\\assistant-x-openclaw';
  }

  String get _venvPythonPath => '$_expandedPath\\venv\\Scripts\\python.exe';
  String get _soundDir => '$_expandedPath\\data\\enrollment';
  String get _speakersFile => '$_soundDir\\speakers.json';

  String _safeDecode(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return SystemEncoding().decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      }
    }
  }

  @override
  Future<List<String>> loadSpeakers() async {
    final file = File(_speakersFile);
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      final List<dynamic> speakers = jsonDecode(content);
      return speakers.map((s) => s['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Stream<String> enrollSpeakerStream() async* {
    final process = await Process.start(
      _venvPythonPath,
      ['$_expandedPath\\scripts\\enroll_speaker.py'],
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );

    await for (final data in process.stdout) {
      final output = _safeDecode(data).trim();
      if (output.isNotEmpty) yield output;
    }

    await for (final data in process.stderr) {
      final output = _safeDecode(data).trim();
      if (output.isNotEmpty) yield output;
    }

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      yield '声纹录入失败 (exit code: $exitCode)';
    }
  }

  @override
  Future<void> deleteSpeaker(String name) async {
    final speakers = await _loadSpeakersData();
    final speaker = speakers.firstWhere(
      (s) => s['name'] == name,
      orElse: () => <String, dynamic>{},
    );

    final wavFile = speaker['wav_file'] as String?;
    if (wavFile != null) {
      final wavPath = '$_soundDir\\$wavFile';
      try {
        await File(wavPath).delete();
      } catch (_) {}
    }

    speakers.removeWhere((s) => s['name'] == name);
    await _saveSpeakersData(speakers);
  }

  @override
  Future<void> clearAllSpeakers() async {
    final result = await Process.run(_venvPythonPath, [
      '$_expandedPath\\scripts\\enroll_speaker.py',
      '--clear'
    ]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }
  }

  Future<List<Map<String, dynamic>>> _loadSpeakersData() async {
    final file = File(_speakersFile);
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      return List<Map<String, dynamic>>.from(jsonDecode(content));
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSpeakersData(List<Map<String, dynamic>> speakers) async {
    final file = File(_speakersFile);
    await file.writeAsString(jsonEncode(speakers));
  }
}
