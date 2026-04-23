abstract class SpeakerServiceBase {
  Future<List<String>> loadSpeakers();
  Stream<String> enrollSpeakerStream();
  Future<void> deleteSpeaker(String name);
  Future<void> clearAllSpeakers();
}