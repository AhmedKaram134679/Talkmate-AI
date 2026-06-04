// Stubbed AgoraService for builds where agora_rtc_engine is disabled (e.g., Windows)
// This preserves the API surface so other parts of the app can compile.

class AgoraService {
  AgoraService._();
  static final AgoraService instance = AgoraService._();

  // Placeholder; in real implementation this would be the Agora engine instance
  dynamic get engine => null;

  Future<void> initialize() async {}
  Future<void> joinAudioChannel({required String channelId}) async {}
  Future<void> joinVideoChannel({required String channelId}) async {}
  Future<void> leave() async {}
  Future<void> muteLocalAudio(bool muted) async {}
  Future<void> enableLocalVideo(bool enabled) async {}
  Future<void> switchCamera() async {}
  Future<void> setSpeakerphoneOn(bool on) async {}
}
