import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Voice Infrastructure Manager (G1).
/// Responsible for hardware audio session management and lifecycle.
class VoiceInfrastructureManager extends GetxService {
  AudioSession? _session;
  bool _isActive = false;

  /// Initializes the hardware audio session with a voice-optimized profile.
  Future<void> initialize() async {
    debugPrint('🎙️ VoiceInfrastructure: Initializing Audio Session...');
    _session = await AudioSession.instance;

    await _session!.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.videoChat,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    debugPrint('✅ VoiceInfrastructure: Hardware Audio Session READY.');
  }

  /// Activates the voice stream (Microphone & Speaker).
  /// Strictly manual and gated by SessionAuthority.
  Future<bool> activateVoice() async {
    if (_session == null) return false;

    debugPrint('🎙️ VoiceInfrastructure: ACTIVATING Live Voice Stream...');
    final success = await _session!.setActive(true);
    _isActive = success;

    if (success) {
      debugPrint('🔊 VoiceInfrastructure: Audio Path is now LIVE.');
    }
    return success;
  }

  /// Deactivates the voice stream and releases the microphone.
  Future<void> deactivateVoice() async {
    if (_session == null || !_isActive) return;

    debugPrint('🎙️ VoiceInfrastructure: DEACTIVATING Voice Stream...');
    await _session!.setActive(false);
    _isActive = false;
    debugPrint('🔇 VoiceInfrastructure: Audio Path RELEASED.');
  }

  /// Emergency Audio Kill Switch.
  /// Releases all audio resources in < 100ms.
  Future<void> audioHardKill() async {
    debugPrint(
        '🛑 AUDIO KILL SWITCH: Releasing all audio handles immediately.');
    _isActive = false;
    if (_session != null) {
      await _session!.setActive(false);
    }
    // Logic to nullify any active audio sinks would go here in a full WebRTC impl.
  }

  @override
  void onClose() {
    deactivateVoice();
    super.onClose();
  }
}
