
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart'; // Provides XFile
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

/// StorageService: wraps Supabase Storage uploads and returns public URLs
/// 
/// CRITICAL FIX: Uses runtime getter for Supabase client instead of early binding.
/// This prevents race conditions during app startup and ensures the client is
/// always fully initialized before being used.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  // CRITICAL FIX: Use getter instead of field initialization
  // This prevents early binding before Supabase is fully initialized
  SupabaseClient get _client => Supabase.instance.client;
  
  static const String _bucket = 'talkmate';

  /// Upload a file from an [XFile] to a storage [path] and return the public URL
  Future<(String url, int size)> uploadFile({
    required XFile file,
    required String path,
    void Function(double progress)? onProgress,
    Map<String, dynamic>? logContext,
  }) async {
    return uploadFileDirect(
      file: File(file.path),
      path: path,
      onProgress: onProgress,
      logContext: logContext,
    );
  }

  /// Upload raw bytes and return URL
  /// 
  /// Includes comprehensive error handling and diagnostics to prevent silent failures.
  Future<(String url, int size)> uploadBytes({
    required List<int> bytes,
    required String path,
    void Function(double progress)? onProgress,
    Map<String, dynamic>? logContext,
  }) async {
    final ctx = logContext ?? {};
    final msgId = (ctx['messageId'] ?? '').toString();
    final taskId = (ctx['taskId'] ?? '').toString();
    final originalFileName = (ctx['originalFileName'] ?? ctx['fileName'] ?? path.split('/').last).toString();
    final fileExtension = p.extension(path).toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');

    // Log STORAGE_UPLOAD_STARTED
    ForensicLogger.log(
      tag: 'STORAGE_UPLOAD_STARTED',
      messageId: msgId,
      localId: msgId,
      taskId: taskId,
      originalFileName: originalFileName,
      generatedStorageKey: path,
      fileExtension: fileExtension,
      status: 'uploading',
    );

    try {
      // Verify Supabase client is initialized
      final client = _client;

      debugPrint('🚀 [StorageService] UPLOAD_STORAGE_START: path=$path, size=${bytes.length} bytes, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}, fileName=${ctx['fileName']}, fileSize=${bytes.length}, localPath=${ctx['localPath']}, currentStatus=${ctx['currentStatus']}, retryCount=${ctx['retryCount']}');

      // Upload binary data to Supabase with a timeout
      await client.storage.from(_bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: _inferContentType(path),
              upsert: true,
            ),
          ).timeout(const Duration(minutes: 5));

      // Get short-lived signed URL (default 24h) for secure private bucket access, fallback to publicUrl
      String url;
      try {
        url = await client.storage
            .from(_bucket)
            .createSignedUrl(path, 60 * 60 * 24);
      } catch (e) {
        debugPrint('⚠️ [StorageService] createSignedUrl fallback to getPublicUrl: $e');
        url = client.storage.from(_bucket).getPublicUrl(path);
      }
      final size = bytes.length;

      debugPrint('✅ [StorageService] UPLOAD_STORAGE_SUCCESS: url=$url, size=$size, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}');

      // Log STORAGE_UPLOAD_COMPLETED
      ForensicLogger.log(
        tag: 'STORAGE_UPLOAD_COMPLETED',
        messageId: msgId,
        localId: msgId,
        taskId: taskId,
        originalFileName: originalFileName,
        generatedStorageKey: path,
        fileExtension: fileExtension,
        status: 'completed',
        remoteUrl: url,
      );

      // Notify progress 100%
      onProgress?.call(1.0);
      debugPrint('🚀 [StorageService] UPLOAD_STORAGE_PROGRESS: taskId=${ctx['taskId']}, progress=100%');

      return (url, size);
    } catch (e, st) {
      debugPrint('❌ [StorageService] UPLOAD_STORAGE_FAILED: path=$path, error=$e, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}');
      debugPrint('❌ [StorageService] Stacktrace: $st');

      // Log STORAGE_UPLOAD_FAILED
      ForensicLogger.log(
        tag: 'STORAGE_UPLOAD_FAILED',
        messageId: msgId,
        localId: msgId,
        taskId: taskId,
        originalFileName: originalFileName,
        generatedStorageKey: path,
        fileExtension: fileExtension,
        status: 'failed',
        extra: e.toString(),
      );

      rethrow;
    }
  }

  /// Upload a file directly without reading into memory (Better for large files)
  Future<(String url, int size)> uploadFileDirect({
    required File file,
    required String path,
    void Function(double progress)? onProgress,
    Map<String, dynamic>? logContext,
  }) async {
    final ctx = logContext ?? {};
    final msgId = (ctx['messageId'] ?? '').toString();
    final taskId = (ctx['taskId'] ?? '').toString();
    final originalFileName = (ctx['originalFileName'] ?? ctx['fileName'] ?? path.split('/').last).toString();
    final fileExtension = p.extension(path).toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');

    // Log STORAGE_UPLOAD_STARTED
    ForensicLogger.log(
      tag: 'STORAGE_UPLOAD_STARTED',
      messageId: msgId,
      localId: msgId,
      taskId: taskId,
      originalFileName: originalFileName,
      generatedStorageKey: path,
      fileExtension: fileExtension,
      status: 'uploading',
    );

    try {
      final client = _client;
      final size = await file.length();
      
      debugPrint('🚀 [StorageService] UPLOAD_STORAGE_START: path=$path, size=$size bytes, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}, fileName=${ctx['fileName']}, fileSize=$size, localPath=${ctx['localPath']}, currentStatus=${ctx['currentStatus']}, retryCount=${ctx['retryCount']}');

      // Upload file directly to Supabase with a timeout
      await client.storage.from(_bucket).upload(
            path,
            file,
            fileOptions: FileOptions(
              contentType: _inferContentType(path),
              upsert: true,
            ),
          ).timeout(const Duration(minutes: 15)); // Increased timeout for large videos

      // Get short-lived signed URL (default 24h) for secure private bucket access, fallback to publicUrl
      String url;
      try {
        url = await client.storage
            .from(_bucket)
            .createSignedUrl(path, 60 * 60 * 24);
      } catch (e) {
        debugPrint('⚠️ [StorageService] createSignedUrl fallback to getPublicUrl: $e');
        url = client.storage.from(_bucket).getPublicUrl(path);
      }

      debugPrint('✅ [StorageService] UPLOAD_STORAGE_SUCCESS: url=$url, size=$size, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}');

      // Log STORAGE_UPLOAD_COMPLETED
      ForensicLogger.log(
        tag: 'STORAGE_UPLOAD_COMPLETED',
        messageId: msgId,
        localId: msgId,
        taskId: taskId,
        originalFileName: originalFileName,
        generatedStorageKey: path,
        fileExtension: fileExtension,
        status: 'completed',
        remoteUrl: url,
      );

      // Notify progress 100%
      onProgress?.call(1.0);
      debugPrint('🚀 [StorageService] UPLOAD_STORAGE_PROGRESS: taskId=${ctx['taskId']}, progress=100%');

      return (url, size);
    } catch (e, st) {
      debugPrint('❌ [StorageService] UPLOAD_STORAGE_FAILED: path=$path, error=$e, taskId=${ctx['taskId']}, messageId=${ctx['messageId']}');
      debugPrint('❌ [StorageService] Stacktrace: $st');

      // Log STORAGE_UPLOAD_FAILED
      ForensicLogger.log(
        tag: 'STORAGE_UPLOAD_FAILED',
        messageId: msgId,
        localId: msgId,
        taskId: taskId,
        originalFileName: originalFileName,
        generatedStorageKey: path,
        fileExtension: fileExtension,
        status: 'failed',
        extra: e.toString(),
      );

      rethrow;
    }
  }

  /// Generate a short-lived signed URL for a file in the private talkmate bucket
  Future<String> getSignedUrl(String path, {int expiresInSeconds = 86400}) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(path, expiresInSeconds);
    } catch (e) {
      debugPrint('⚠️ [StorageService] getSignedUrl fallback: $e');
      return _client.storage.from(_bucket).getPublicUrl(path);
    }
  }

  String _inferContentType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.m4a')) return 'audio/mp4';
    if (p.endsWith('.aac')) return 'audio/aac';
    if (p.endsWith('.wav')) return 'audio/wav';
    if (p.endsWith('.pdf')) return 'application/pdf';
    if (p.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
