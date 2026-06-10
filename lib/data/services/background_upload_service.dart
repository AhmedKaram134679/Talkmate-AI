import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/services/upload_manager.dart';

/// Background upload service that manages uploads independently from UI lifecycle
class BackgroundUploadService {
  static final BackgroundUploadService _instance = BackgroundUploadService._internal();
  
  factory BackgroundUploadService() {
    return _instance;
  }
  
  BackgroundUploadService._internal();
  
  final UploadManager _uploadManager = UploadManager();
  Timer? _uploadWorker;
  bool _isInitialized = false;
  
  /// Initialize background upload service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _uploadManager.initialize();
      _startUploadWorker();
      _isInitialized = true;
      debugPrint('✅ [BackgroundUploadService] Initialized');
    } catch (e, st) {
      debugPrint('❌ [BackgroundUploadService] Initialization failed: $e');
      debugPrint('❌ [BackgroundUploadService] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Start background upload worker
  void _startUploadWorker() {
    _uploadWorker?.cancel();
    _uploadWorker = Timer.periodic(Duration(seconds: 2), (timer) {
      _processUploadQueue();
    });
    debugPrint('🔄 [BackgroundUploadService] Upload worker started');
  }
  
  /// Process upload queue (called periodically)
  Future<void> _processUploadQueue() async {
    try {
      // Check if there are pending uploads
      final queueStatus = _uploadManager.getQueueStatus();
      if (queueStatus['total'] > 0 && !queueStatus['processing']) {
        debugPrint('📤 [BackgroundUploadService] UPLOAD_WORKER_PICKED_TASK: Found pending tasks, starting processor');
        _uploadManager.processQueue().ignore();
      }
    } catch (e) {
      debugPrint('⚠️ [BackgroundUploadService] UPLOAD_WORKER_ERROR: $e');
    }
  }
  
  /// Add upload (independent of UI lifecycle)
  Future<void> addUpload({
    required String messageId,
    required String chatId,
    required String userId,
    required String localFilePath,
    required String uploadPath,
    required String mediaType,
    String? fileName,
  }) async {
    try {
      debugPrint('📤 [BackgroundUploadService] UPLOAD_TASK_ENQUEUED: messageId=$messageId, fileName=$fileName, fileSize=unknown, localPath=$localFilePath, currentStatus=queued, retryCount=0');
      await _uploadManager.addUpload(
        messageId: messageId,
        chatId: chatId,
        userId: userId,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        mediaType: mediaType,
        fileName: fileName,
      );
    } catch (e, st) {
      debugPrint('❌ [BackgroundUploadService] UPLOAD_TASK_FAILED: messageId=$messageId, error=$e');
      debugPrint('❌ [BackgroundUploadService] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Get upload progress (observable)
  RxDouble getUploadProgressObservable(String messageId) {
    return _uploadManager.uploadProgressMap[messageId] ?? RxDouble(0.0);
  }
  
  /// Get upload status (observable)
  RxString getUploadStatusObservable(String messageId) {
    return _uploadManager.uploadStatusMap[messageId] ?? RxString('unknown');
  }
  
  /// Retry failed upload
  Future<void> retryUpload(String messageId) async {
    await _uploadManager.retryUpload(messageId);
  }
  
  /// Cancel upload
  void cancelUpload(String messageId) {
    _uploadManager.cancelUpload(messageId);
  }
  
  /// Get queue status
  Map<String, dynamic> getQueueStatus() {
    return _uploadManager.getQueueStatus();
  }
  
  /// Pause all uploads
  void pauseAllUploads() {
    debugPrint('⏸️ [BackgroundUploadService] Pausing all uploads');
    _uploadWorker?.cancel();
  }
  
  /// Resume all uploads
  void resumeAllUploads() {
    if (!_isInitialized) return;
    debugPrint('▶️ [BackgroundUploadService] Resuming all uploads');
    _startUploadWorker();
  }
  
  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
  
  /// Dispose service
  void dispose() {
    _uploadWorker?.cancel();
    _uploadManager.dispose();
    _isInitialized = false;
    debugPrint('🛑 [BackgroundUploadService] Disposed');
  }
}

/// Upload worker that processes uploads in background
class UploadWorker {
  static final UploadWorker _instance = UploadWorker._internal();
  
  factory UploadWorker() {
    return _instance;
  }
  
  UploadWorker._internal();
  
  final BackgroundUploadService _service = BackgroundUploadService();
  Timer? _heartbeat;
  
  /// Start upload worker
  Future<void> start() async {
    try {
      await _service.initialize();
      _startHeartbeat();
      debugPrint('✅ [UploadWorker] Started');
    } catch (e, st) {
      debugPrint('❌ [UploadWorker] Failed to start: $e');
      debugPrint('❌ [UploadWorker] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Start heartbeat monitoring
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(Duration(seconds: 5), (timer) {
      final queueStatus = _service.getQueueStatus();
      debugPrint('💓 [UploadWorker] Heartbeat - Queue: ${queueStatus['total']}, Processing: ${queueStatus['processing']}');
    });
  }
  
  /// Stop upload worker
  void stop() {
    _heartbeat?.cancel();
    _service.pauseAllUploads();
    debugPrint('🛑 [UploadWorker] Stopped');
  }
  
  /// Check worker status
  bool get isRunning => _heartbeat?.isActive ?? false;
  
  /// Resume worker after pause
  void resume() {
    if (!isRunning) {
      _startHeartbeat();
      _service.resumeAllUploads();
      debugPrint('▶️ [UploadWorker] Resumed');
    }
  }
  
  /// Dispose worker
  void dispose() {
    _heartbeat?.cancel();
    _service.dispose();
    debugPrint('🛑 [UploadWorker] Disposed');
  }
}
