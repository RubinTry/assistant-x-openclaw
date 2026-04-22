import 'dart:convert';
import 'dart:io';
import '../base/speaker_service_base.dart';

class MacOSSpeakerService implements SpeakerServiceBase {
  String get _expandedPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.openclaw/workspace/voice-assistant/assistant-x-openclaw';
  }

  String get _venvPythonPath => '$_expandedPath/venv/bin/python';
  String get _soundDir => '$_expandedPath/data/enrollment';
  String get _speakersFile => '$_soundDir/speakers.json';

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
      ['$_expandedPath/scripts/enroll_speaker.py'],
    );

    yield* process.stdout.transform(utf8.decoder).map((data) => data.trim()).where((data) => data.isNotEmpty);
    yield* process.stderr.transform(utf8.decoder).map((data) => data.trim()).where((data) => data.isNotEmpty);

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
      final wavPath = '$_soundDir/$wavFile';
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
      '$_expandedPath/scripts/enroll_speaker.py',
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