import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

class VideoThumbnailHelper {
  /// Generate a thumbnail for a video and return its absolute local path.
  static Future<String?> generateThumbnail({
    required String videoPath,
    required String messageId,
    String? chatId,
  }) async {
    Player? player;
    try {
      ForensicLogger.log(
        tag: 'VIDEO_SELECTED',
        messageId: messageId,
        chatId: chatId,
        localPath: videoPath,
        status: 'generating_thumbnail',
      );

      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        debugPrint('⚠️ [VideoThumbnailHelper] Video file not found: $videoPath');
        return null;
      }

      final size = await videoFile.length();
      final fileName = p.basename(videoPath);

      player = Player();

      final completer = Completer<void>();
      final widthSub = player.stream.width.listen((width) {
        if (width != null && width > 0 && !completer.isCompleted) {
          completer.complete();
        }
      });

      // Load video in media_kit player (play = false)
      await player.open(Media(videoPath), play: false);

      // Wait up to 3 seconds for metadata to load
      try {
        await completer.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        debugPrint('⚠️ [VideoThumbnailHelper] Timeout waiting for video dimensions');
      }
      await widthSub.cancel();

      // Seek to 1 second or Duration.zero depending on length
      final duration = player.state.duration;
      final seekPos = duration > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : Duration.zero;
      await player.seek(seekPos);

      // Take frame capture
      final Uint8List? frameBytes = await player.screenshot();
      if (frameBytes == null || frameBytes.isEmpty) {
        debugPrint('⚠️ [VideoThumbnailHelper] Screenshot bytes are null or empty');
        return null;
      }

      // Save to permanent documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final thumbsDir = Directory(p.join(appDir.path, 'thumbnails'));
      if (!thumbsDir.existsSync()) {
        thumbsDir.createSync(recursive: true);
      }

      final thumbFile = File(p.join(thumbsDir.path, '${messageId}_thumb.jpg'));
      await thumbFile.writeAsBytes(frameBytes);

      ForensicLogger.log(
        tag: 'VIDEO_THUMBNAIL_CREATED',
        messageId: messageId,
        chatId: chatId,
        fileName: fileName,
        fileSize: size,
        localPath: videoPath,
        thumbnailPath: thumbFile.path,
        status: 'thumbnail_created',
      );

      return thumbFile.path;
    } catch (e, st) {
      debugPrint('❌ [VideoThumbnailHelper] Thumbnail generation failed: $e\n$st');
      return null;
    } finally {
      if (player != null) {
        await player.dispose();
      }
    }
  }
}
