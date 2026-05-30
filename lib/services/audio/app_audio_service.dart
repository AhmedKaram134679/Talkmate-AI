import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:talkmate_ai/services/audio/audio_extractor.dart';

class AppAudioService extends GetxService {
  static AppAudioService get instance => Get.find<AppAudioService>();

  final Map<String, Player> _players = {};
  final AudioExtractor _extractor = AudioExtractor();

  /// Initializes the service by extracting assets to the local filesystem.
  Future<void> init() async {
    debugPrint('🔊 AppAudioService: Initializing...');
    await _extractor.init();
    debugPrint('🔊 AppAudioService: Initialization complete.');
  }

  @override
  void onClose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    super.onClose();
  }

  /// Lists all available audio output devices.
  Future<List<AudioDevice>> getAvailableOutputs() async {
    try {
      // Use a temporary player to get the state if needed, or use a default one
      final tempPlayer = Player();
      final devices = tempPlayer.state.audioDevices;
      await tempPlayer.dispose();
      return devices;
    } catch (e) {
      debugPrint('⚠️ AppAudioService: Error enumerating devices: $e');
      return [];
    }
  }

  /// Configures a specific player to use a specific output device.
  Future<void> setAudioDevice(String filename, AudioDevice device) async {
    final player = _getOrCreatePlayer(filename);
    try {
      await player.setAudioDevice(device);
      debugPrint(
          '🔊 AppAudioService: Player for $filename set to device: ${device.description}');
    } catch (e) {
      debugPrint(
          '⚠️ AppAudioService: Failed to set audio device for $filename: $e');
    }
  }

  /// Plays a sound by its filename.
  /// The file must exist in the extracted audio directory.
  Future<void> play(String filename,
      {bool loop = false, double volume = 100.0, bool wait = false}) async {
    try {
      final path = _extractor.getAudioPath(filename);
      if (path == null) {
        debugPrint('⚠️ AppAudioService: Audio path not found for $filename');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('⚠️ AppAudioService: File does not exist at path: $path');
        return;
      }

      final player = _getOrCreatePlayer(filename);

      // Configure player
      await player.setVolume(volume);
      await player
          .setPlaylistMode(loop ? PlaylistMode.loop : PlaylistMode.none);

      // Open and play
      await player.open(Media(path));
      debugPrint('✅ AppAudioService: Playing $filename from $path');

      if (wait) {
        await _awaitCompletion(player);
      }
    } catch (e) {
      debugPrint('❌ AppAudioService: Error playing $filename: $e');
    }
  }

  Future<void> _awaitCompletion(Player player) async {
    await player.stream.completed.firstWhere((c) => c == true);
  }

  /// Stops a specific sound by its filename.
  Future<void> stop(String filename) async {
    final player = _players[filename];
    if (player != null) {
      await player.stop();
      debugPrint('🛑 AppAudioService: Stopped $filename');
    }
  }

  /// Stops all currently playing sounds.
  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.stop();
    }
    debugPrint('🛑 AppAudioService: Stopped all sounds.');
  }

  /// Specialized method for speaker test to ensure completion event.
  Future<void> playSpeakerTest(String filename) async {
    debugPrint('🔊 AppAudioService: Running speaker test for $filename');
    await play(filename, volume: 100.0);
  }

  Player _getOrCreatePlayer(String filename) {
    if (!_players.containsKey(filename)) {
      final player = Player();
      _players[filename] = player;
      debugPrint('🔊 AppAudioService: Created new Player for $filename');
    }
    return _players[filename]!;
  }

  /// Emergency reset of all players
  Future<void> resetAll() async {
    debugPrint('🔊 AppAudioService: Resetting all players...');
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
