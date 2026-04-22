import '../base/speaker_service_base.dart';

class LinuxSpeakerService implements SpeakerServiceBase {
  @override
  Future<List<String>> loadSpeakers() async => [];
  @override
  Stream<String> enrollSpeakerStream() async* {}
  @override
  Future<void> deleteSpeaker(String name) async {}
  @override
  Future<void> clearAllSpeakers() async {}
}