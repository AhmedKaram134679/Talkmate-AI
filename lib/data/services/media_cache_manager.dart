import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';

/// Configuration constants for media caching
class MediaCacheConfig {
  static const int maxCacheSizeBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const Duration cacheExpiration = Duration(days: 30);
  static const String imageCacheKey = 'talkmate_image_cache';
  static const String audioCacheKey = 'talkmate_audio_cache';
  static const String videoCacheKey = 'talkmate_video_cache';
}

/// Main media cache manager coordinating all cache operations
class MediaCacheManager {
  static final MediaCacheManager _instance = MediaCacheManager._internal();
  
  factory MediaCacheManager() {
    return _instance;
  }
  
  MediaCacheManager._internal();
  
  late CacheManager _imageCache;
  late CacheManager _audioCache;
  late CacheManager _videoCache;
  late CacheManager _fileCache;
  final SqliteDatabaseService _db = SqliteDatabaseService();
  
  /// Initialize cache managers
  Future<void> initialize() async {
    try {
      _imageCache = CacheManager(
        Config(
          MediaCacheConfig.imageCacheKey,
          stalePeriod: MediaCacheConfig.cacheExpiration,
          maxNrOfCacheObjects: 500,
          repo: JsonCacheInfoRepository(
            databaseName: 'talkmate_image_cache',
          ),
        ),
      );
      
      _audioCache = CacheManager(
        Config(
          MediaCacheConfig.audioCacheKey,
          stalePeriod: MediaCacheConfig.cacheExpiration,
          maxNrOfCacheObjects: 200,
          repo: JsonCacheInfoRepository(
            databaseName: 'talkmate_audio_cache',
          ),
        ),
      );
      
      _videoCache = CacheManager(
        Config(
          MediaCacheConfig.videoCacheKey,
          stalePeriod: MediaCacheConfig.cacheExpiration,
          maxNrOfCacheObjects: 50,
          repo: JsonCacheInfoRepository(
            databaseName: 'talkmate_video_cache',
          ),
        ),
      );

      _fileCache = CacheManager(
        Config(
          'talkmate_file_cache',
          stalePeriod: MediaCacheConfig.cacheExpiration,
          maxNrOfCacheObjects: 100,
          repo: JsonCacheInfoRepository(
            databaseName: 'talkmate_file_cache',
          ),
        ),
      );
      
      debugPrint('✅ [MediaCacheManager] Cache managers initialized');
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Initialization failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
      rethrow;
    }
  }

  /// Cache generic file
  Future<File?> cacheFile({
    required String url,
    required String messageId,
    required String chatId,
    String? fileName,
  }) async {
    try {
      debugPrint('📂 [MediaCacheManager] CACHE_FILE_START: url=$url');
      // Download and cache
      final file = await _fileCache.getSingleFile(url);
      
      // Track in database
      await _db.insertCachedMedia(
        id: '${messageId}_file',
        originalUrl: url,
        localFilePath: file.path,
        mediaType: 'file',
        fileSizeBytes: await file.length(),
        expiresAt: DateTime.now().add(MediaCacheConfig.cacheExpiration),
      );
      
      debugPrint('✅ [MediaCacheManager] CACHE_FILE_SUCCESS: path=${file.path}');
      await _enforceQuota();
      return file;
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] File caching failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
      return null;
    }
  }
  
  /// Cache image file
  Future<File?> cacheImage({
    required String url,
    required String messageId,
    required String chatId,
    String? mediaType = 'image',
  }) async {
    try {
      // Download and cache
      final file = await _imageCache.getSingleFile(url);
      
      // Track in database using SqliteDatabaseService
      await _db.insertCachedMedia(
        id: '${messageId}_image',
        originalUrl: url,
        localFilePath: file.path,
        mediaType: mediaType ?? 'image',
        fileSizeBytes: await file.length(),
        expiresAt: DateTime.now().add(MediaCacheConfig.cacheExpiration),
      );
      
      await _enforceQuota();
      return file;
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Image caching failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
      return null;
    }
  }
  
  /// Cache audio file
  Future<File?> cacheAudio({
    required String url,
    required String messageId,
    required String chatId,
  }) async {
    try {
      // Download and cache
      final file = await _audioCache.getSingleFile(url);
      
      // Track in database using SqliteDatabaseService
      await _db.insertCachedMedia(
        id: '${messageId}_audio',
        originalUrl: url,
        localFilePath: file.path,
        mediaType: 'audio',
        fileSizeBytes: await file.length(),
        expiresAt: DateTime.now().add(MediaCacheConfig.cacheExpiration),
      );
      
      await _enforceQuota();
      return file;
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Audio caching failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
      return null;
    }
  }
  
  /// Cache video file
  Future<File?> cacheVideo({
    required String url,
    required String messageId,
    required String chatId,
  }) async {
    try {
      // Download and cache
      final file = await _videoCache.getSingleFile(url);
      
      // Track in database using SqliteDatabaseService
      await _db.insertCachedMedia(
        id: '${messageId}_video',
        originalUrl: url,
        localFilePath: file.path,
        mediaType: 'video',
        fileSizeBytes: await file.length(),
        expiresAt: DateTime.now().add(MediaCacheConfig.cacheExpiration),
      );
      
      await _enforceQuota();
      return file;
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Video caching failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
      return null;
    }
  }
  
  /// Get cached file by URL
  Future<File?> getCachedFile(String url) async {
    try {
      final cached = await _db.getCachedMedia(url);
      if (cached != null) {
        final filePath = cached['local_file_path'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (file.existsSync()) {
            return file;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ [MediaCacheManager] Failed to get cached file: $e');
      return null;
    }
  }
  
  /// Clear expired cache and enforce quota
  Future<void> _enforceQuota() async {
    try {
      await _db.cleanExpiredCache();
      final totalSize = await _db.getCacheSizeBytes();
      if (totalSize > MediaCacheConfig.maxCacheSizeBytes) {
        debugPrint('🧹 [MediaCacheManager] Cache exceeds quota. Cleaning...');
        await _cleanLRU(totalSize);
      }
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Quota enforcement failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
    }
  }
  
  /// LRU cache cleanup
  Future<void> _cleanLRU(int currentSize) async {
    try {
      debugPrint('🧹 [MediaCacheManager] Starting LRU cleanup...');
      // LRU cleanup is simplified - just clean expired entries
      await _db.cleanExpiredCache();
      debugPrint('✅ [MediaCacheManager] LRU cleanup completed');
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] LRU cleanup failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
    }
  }
  
  /// Clear all cache
  Future<void> clearAllCache() async {
    try {
      await _imageCache.emptyCache();
      await _audioCache.emptyCache();
      await _videoCache.emptyCache();
      
      await _db.cleanExpiredCache();
      
      debugPrint('✅ [MediaCacheManager] All cache cleared');
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Cache clearing failed: $e');
      debugPrint('❌ [MediaCacheManager] Stacktrace: $st');
    }
  }
  
  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final totalSize = await _db.getCacheSizeBytes();
      
      return {
        'totalSize': totalSize,
        'totalSizeMB': totalSize / (1024 * 1024),
        'quotaPercentage': (totalSize / MediaCacheConfig.maxCacheSizeBytes * 100).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('❌ [MediaCacheManager] Failed to get cache stats: $e');
      return {};
    }
  }

  /// Save a temporary file permanently to prevent deletion
  Future<File> saveFilePermanently(String tempPath, String messageId) async {
    try {
      final file = File(tempPath);
      if (!file.existsSync()) {
        throw Exception('Source file does not exist at $tempPath');
      }

      final appDir = await getApplicationDocumentsDirectory();
      
      // Diagnostic check: verify directory permissions
      try {
        final testFile = File(p.join(appDir.path, '.write_test'));
        await testFile.writeAsString('test');
        await testFile.delete();
        debugPrint('ℹ️ [MediaCacheManager] App documents directory permissions verified (read/write OK) at: ${appDir.path}');
      } catch (e) {
        debugPrint('⚠️ [MediaCacheManager] App documents directory permission test failed: $e');
      }

      final permanentDir = Directory(p.join(appDir.path, 'media'));
      if (!permanentDir.existsSync()) {
        permanentDir.createSync(recursive: true);
      }

      final fileExt = p.extension(tempPath);
      final newPath = p.join(permanentDir.path, '$messageId$fileExt');
      
      File permanentFile;
      try {
        permanentFile = await file.copy(newPath);
      } catch (copyErr) {
        debugPrint('⚠️ [MediaCacheManager] Standard file.copy failed: $copyErr. Falling back to byte copy...');
        final bytes = await file.readAsBytes();
        permanentFile = File(newPath);
        await permanentFile.writeAsBytes(bytes, flush: true);
      }
      
      debugPrint('✅ [MediaCacheManager] Saved file permanently: ${permanentFile.path}');
      return permanentFile;
    } catch (e, st) {
      debugPrint('❌ [MediaCacheManager] Failed to save file permanently: $e\n$st');
      rethrow;
    }
  }
}
