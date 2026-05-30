import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioExtractor {
  static final AudioExtractor _instance = AudioExtractor._internal();
  factory AudioExtractor() => _instance;
  AudioExtractor._internal();

  String? _audioDirPath;
  String? get audioDirPath => _audioDirPath;

  /// Extracts all audio assets to the local application support directory.
  Future<void> init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _audioDirPath = p.join(supportDir.path, 'audio');
      final directory = Directory(_audioDirPath!);

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // We explicitly list the assets we know exist to avoid complex manifest parsing
      // which can be flaky across Flutter versions.
      final List<String> assets = [
        'audio_record_start.mp3',
        'audio_record_stop.mp3',
        'call_incomming.mp3',
        'call_ringtone.mp3',
        'friend_request.mp3',
        'group_join_notification.mp3',
        'message_receive.mp3',
        'message_send.mp3',
        'new_notification.mp3',
      ];

      for (final assetName in assets) {
        await _extractAsset(assetName);
      }

      debugPrint('🔊 AudioExtractor: Initialization and extraction complete.');
    } catch (e) {
      debugPrint('❌ AudioExtractor: Error during initialization: $e');
    }
  }

  Future<void> _extractAsset(String assetName) async {
    final assetPath = 'assets/sounds/$assetName';
    final targetPath = p.join(_audioDirPath!, assetName);
    final targetFile = File(targetPath);

    // Check if file already exists to avoid redundant copying
    if (await targetFile.exists()) {
      // Optional: Check file size or hash if we want to support asset updates
      // For now, simple existence check is enough for performance.
      return;
    }

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await targetFile.writeAsBytes(bytes);
      debugPrint('✅ AudioExtractor: Extracted $assetName to local storage.');
    } catch (e) {
      debugPrint('⚠️ AudioExtractor: Failed to extract $assetName: $e');
    }
  }

  /// Returns the absolute path for a given audio file name.
  String? getAudioPath(String filename) {
    if (_audioDirPath == null) return null;
    return p.join(_audioDirPath!, filename);
  }
}
