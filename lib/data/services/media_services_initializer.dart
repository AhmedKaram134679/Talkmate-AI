import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:talkmate_ai/data/services/background_upload_service.dart';
import 'package:talkmate_ai/data/services/connectivity_monitor.dart';
import 'package:talkmate_ai/data/services/database_service_native.dart';
import 'package:talkmate_ai/data/services/instant_preview_service.dart';
import 'package:talkmate_ai/data/services/media_cache_manager.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';
import 'package:talkmate_ai/data/services/upload_recovery_manager.dart';
import 'package:talkmate_ai/services/audio/audio_queue_manager.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

/// Master initialization service for all media services
class MediaServicesInitializer {
  static final MediaServicesInitializer _instance = MediaServicesInitializer._internal();
  
  factory MediaServicesInitializer() {
    return _instance;
  }
  
  MediaServicesInitializer._internal();
  
  // Service instances
  late SqliteDatabaseService _databaseService;
  late MediaStateStore _stateStore;
  late MediaCacheManager _cacheManager;
  late BackgroundUploadService _backgroundUploadService;
  late UploadRecoveryManager _recoveryManager;
  late InstantPreviewService _previewService;
  late ConnectivityMonitor _connectivityMonitor;
  late OfflineUploadRecovery _offlineRecovery;
  late AudioQueueManager _audioQueueManager;
  
  bool _isInitialized = false;
  
  /// Initialize all media services
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ [MediaServicesInitializer] Already initialized');
      return;
    }
    
    try {
      debugPrint('🚀 [MediaServicesInitializer] Starting initialization...');
      
      // Phase 1: SQLite database initialization
      _databaseService = SqliteDatabaseService();
      await _databaseService.database; // Pre-warm connection
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 1.5: Unified Media State Store initialization
      // This is the Single Source of Truth, must be ready before other services
      _stateStore = Get.put(MediaStateStore());
      await _stateStore.init();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 2: Cache manager
      _cacheManager = MediaCacheManager();
      await _cacheManager.initialize();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 3: Upload manager
      _backgroundUploadService = BackgroundUploadService();
      await _backgroundUploadService.initialize();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 4: Recovery manager
      _recoveryManager = UploadRecoveryManager();
      await _recoveryManager.initialize();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 5: Instant preview service
      _previewService = InstantPreviewService();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 6: Connectivity monitoring
      _connectivityMonitor = ConnectivityMonitor();
      await _connectivityMonitor.initialize();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 7: Offline recovery
      _offlineRecovery = OfflineUploadRecovery();
      await _offlineRecovery.initialize();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Phase 8: Audio queue manager
      _audioQueueManager = AudioQueueManager();
      await _audioQueueManager.initialize();

      // Forensic Audit: Log Startup Event
      ForensicLogger.log(
        tag: 'VIDEO_APP_STARTUP',
        messageId: 'N/A',
        localId: 'N/A',
        chatId: 'N/A',
        taskId: 'N/A',
        filename: 'N/A',
        localFilePath: 'N/A',
        thumbnailPath: 'N/A',
        remoteUrl: 'N/A',
        status: 'startup',
        uploadProgress: 0.0,
      );

      // Forensic Audit: Database Counts & Video Records
      try {
        final dbMedia = await _databaseService.database;
        final dbCore = await DatabaseService.instance.database;

        final pendingUploadCount = Sqflite.firstIntValue(
              await dbMedia.rawQuery('SELECT COUNT(*) FROM pending_uploads'),
            ) ??
            0;
        final mediaStateCount = Sqflite.firstIntValue(
              await dbMedia.rawQuery('SELECT COUNT(*) FROM media_states'),
            ) ??
            0;
        final localMessageCount = Sqflite.firstIntValue(
              await dbCore.rawQuery('SELECT COUNT(*) FROM local_messages'),
            ) ??
            0;

        debugPrint('📊 [MediaServicesInitializer] PENDING_UPLOAD_COUNT: $pendingUploadCount');
        debugPrint('📊 [MediaServicesInitializer] MEDIA_STATE_COUNT: $mediaStateCount');
        debugPrint('📊 [MediaServicesInitializer] LOCAL_MESSAGE_COUNT: $localMessageCount');

        final pendingVideos = await dbMedia.query('pending_uploads', where: "media_type = 'video'");
        debugPrint('🎥 [MediaServicesInitializer] --- PENDING VIDEOS DUMP ---');
        for (final row in pendingVideos) {
          debugPrint('🎥 [MediaServicesInitializer] Pending video record: $row');
        }
        debugPrint('🎥 [MediaServicesInitializer] ------------------------');
      } catch (e) {
        debugPrint('❌ [MediaServicesInitializer] Startup database audit failed: $e');
      }
      
      _isInitialized = true;
      
      debugPrint('✅ [MediaServicesInitializer] All services initialized');
      _printInitializationSummary();
    } catch (e, st) {
      debugPrint('❌ [MediaServicesInitializer] Initialization failed: $e');
      debugPrint('❌ [MediaServicesInitializer] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Print initialization summary
  void _printInitializationSummary() {
    debugPrint('''
╔════════════════════════════════════════════════╗
║   Media Services Initialization Complete       ║
╠════════════════════════════════════════════════╣
║ ✅ SQLite Database Service
║ ✅ Media Cache Manager
║ ✅ Background Upload Service
║ ✅ Upload Recovery Manager
║ ✅ Instant Preview Service
║ ✅ Connectivity Monitor
║ ✅ Offline Upload Recovery
║ ✅ Audio Queue Manager
╚════════════════════════════════════════════════╝
    ''');
  }
  
  // Service getters
  SqliteDatabaseService get database => _databaseService;
  MediaCacheManager get cacheManager => _cacheManager;
  BackgroundUploadService get backgroundUpload => _backgroundUploadService;
  UploadRecoveryManager get recoveryManager => _recoveryManager;
  InstantPreviewService get previewService => _previewService;
  ConnectivityMonitor get connectivityMonitor => _connectivityMonitor;
  OfflineUploadRecovery get offlineRecovery => _offlineRecovery;
  AudioQueueManager get audioQueue => _audioQueueManager;
  
  /// Check if services are initialized
  bool get isInitialized => _isInitialized;
  
  /// Dispose all services
  Future<void> dispose() async {
    try {
      debugPrint('🛑 [MediaServicesInitializer] Disposing all services...');
      
      _audioQueueManager.dispose();
      _offlineRecovery.dispose();
      _connectivityMonitor.dispose();
      _backgroundUploadService.dispose();
      _recoveryManager.dispose();
      await _cacheManager.clearAllCache();
      await _databaseService.close();

      // Forensic Audit: Log Shutdown Event
      ForensicLogger.log(
        tag: 'VIDEO_APP_SHUTDOWN',
        messageId: 'N/A',
        localId: 'N/A',
        chatId: 'N/A',
        taskId: 'N/A',
        filename: 'N/A',
        localFilePath: 'N/A',
        thumbnailPath: 'N/A',
        remoteUrl: 'N/A',
        status: 'shutdown',
        uploadProgress: 0.0,
      );
      
      _isInitialized = false;
      debugPrint('✅ [MediaServicesInitializer] All services disposed');
    } catch (e, st) {
      debugPrint('❌ [MediaServicesInitializer] Disposal failed: $e');
      debugPrint('❌ [MediaServicesInitializer] Stacktrace: $st');
    }
  }
}

/// Lazy loader for image optimization
class LazyImageLoader {
  /// Load image with lazy loading and caching
  static Future<ImageProvider<Object>> loadImage({
    required String url,
    required String messageId,
    required String chatId,
    required MediaCacheManager cacheManager,
  }) async {
    try {
      // Try to get from cache first
      final cachedFile = await cacheManager.getCachedFile(url);
      if (cachedFile != null) {
        return FileImage(cachedFile);
      }
      
      // Cache image for next time
      unawaited(
        cacheManager.cacheImage(
          url: url,
          messageId: messageId,
          chatId: chatId,
        ),
      );
      
      // Return network image immediately
      return NetworkImage(url);
    } catch (e) {
      debugPrint('❌ [LazyImageLoader] Failed to load image: $e');
      return NetworkImage(url);
    }
  }
}

/// Global function helper
void unawaited(Future<void> future) {
  future.ignore();
}
