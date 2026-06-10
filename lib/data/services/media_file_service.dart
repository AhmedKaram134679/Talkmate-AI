import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:talkmate_ai/data/services/media_cache_manager.dart';

/// Service for handling cross-platform file opening and downloading
class MediaFileService {
  static final MediaFileService instance = MediaFileService._();
  MediaFileService._();

  final MediaCacheManager _cacheManager = MediaCacheManager();

  /// Open a file from a URL. Downloads and caches if necessary.
  Future<void> openFile({
    required String url,
    required String messageId,
    required String chatId,
  }) async {
    try {
      debugPrint('📂 [MediaFileService] FILE_OPEN_REQUEST: url=$url');

      // 1. Check if it's a local path already
      if (url.startsWith('/') || url.contains(':\\') || url.startsWith('file://')) {
        String cleanPath = url;
        if (url.startsWith('file://')) {
          cleanPath = Uri.parse(url).toFilePath();
        }
        final localFile = File(cleanPath);
        if (localFile.existsSync()) {
          await _openLocalFile(localFile.path);
          return;
        }
      }

      // 2. Handle non-http URLs (e.g. malformed or asset paths)
      if (!url.startsWith('http')) {
        debugPrint('⚠️ [MediaFileService] Invalid URL scheme: $url');
        throw Exception('Invalid file URL');
      }

      // 2. Check cache
      File? file = await _cacheManager.getCachedFile(url);
      
      if (file == null || !file.existsSync()) {
        debugPrint('📂 [MediaFileService] FILE_DOWNLOAD_START: url=$url');
        file = await _cacheManager.cacheFile(
          url: url,
          messageId: messageId,
          chatId: chatId,
        );
      }

      if (file != null && file.existsSync()) {
        debugPrint('📂 [MediaFileService] FILE_DOWNLOAD_SUCCESS: path=${file.path}');
        await _openLocalFile(file.path);
      } else {
        throw Exception('Could not download or find file');
      }
    } catch (e, st) {
      debugPrint('❌ [MediaFileService] FILE_OPEN_FAILED: $e');
      debugPrint('❌ [MediaFileService] Stacktrace: $st');
      rethrow;
    }
  }

  /// Internal helper to open local file using open_filex
  Future<void> _openLocalFile(String path) async {
    try {
      debugPrint('📂 [MediaFileService] FILE_OPEN_ATTEMPT: path=$path');
      final result = await OpenFilex.open(path);
      if (result.type == ResultType.done) {
        debugPrint('✅ [MediaFileService] FILE_OPEN_SUCCESS: path=$path');
      } else {
        debugPrint('❌ [MediaFileService] FILE_OPEN_FAILED: type=${result.type}, message=${result.message}');
        throw Exception('Could not open file: ${result.message}');
      }
    } catch (e) {
      debugPrint('❌ [MediaFileService] FILE_OPEN_CRITICAL_ERROR: path=$path, error=$e');
      rethrow;
    }
  }
}
