import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/services/background_upload_service.dart';

/// Monitors connectivity and manages offline/online transitions
class ConnectivityMonitor {
  static final ConnectivityMonitor _instance = ConnectivityMonitor._internal();
  
  factory ConnectivityMonitor() {
    return _instance;
  }
  
  ConnectivityMonitor._internal();
  
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;
  
  final RxBool isOnline = true.obs;
  final RxBool wasOffline = false.obs;
  final Rx<ConnectivityResult> lastResult = ConnectivityResult.other.obs;
  
  /// Initialize connectivity monitor
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      final results = await _connectivity.checkConnectivity();
      final result = results.isNotEmpty ? results.first : ConnectivityResult.other;
      _updateConnectivityStatus(result);
      
      // Listen for changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _onConnectivityChanged,
      );
      
      debugPrint('✅ [ConnectivityMonitor] Initialized');
    } catch (e, st) {
      debugPrint('❌ [ConnectivityMonitor] Initialization failed: $e');
      debugPrint('❌ [ConnectivityMonitor] Stacktrace: $st');
    }
  }
  
  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final result = results.isNotEmpty ? results.first : ConnectivityResult.other;
    final wasOnlineBefore = isOnline.value;
    _updateConnectivityStatus(result);
    
    // Detect transition from offline to online
    if (!wasOnlineBefore && isOnline.value) {
      debugPrint('📡 [ConnectivityMonitor] Back online - initiating recovery');
      _handleReconnection();
    } else if (wasOnlineBefore && !isOnline.value) {
      debugPrint('📡 [ConnectivityMonitor] Going offline - pausing uploads');
      _handleDisconnection();
    }
  }
  
  /// Update connectivity status
  void _updateConnectivityStatus(ConnectivityResult result) {
    lastResult.value = result;
    
    final online = result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet;
    
    isOnline.value = online;
    
    if (!online && !wasOffline.value) {
      wasOffline.value = true;
    }
  }
  
  /// Handle reconnection
  void _handleReconnection() {
    try {
      final uploadService = BackgroundUploadService();
      uploadService.resumeAllUploads();
      
      debugPrint('✅ [ConnectivityMonitor] Uploads resumed after reconnection');
    } catch (e) {
      debugPrint('⚠️ [ConnectivityMonitor] Failed to resume uploads: $e');
    }
  }
  
  /// Handle disconnection
  void _handleDisconnection() {
    try {
      final uploadService = BackgroundUploadService();
      uploadService.pauseAllUploads();
      
      debugPrint('⏸️ [ConnectivityMonitor] Uploads paused due to disconnection');
    } catch (e) {
      debugPrint('⚠️ [ConnectivityMonitor] Failed to pause uploads: $e');
    }
  }
  
  /// Get connectivity status display text
  String getStatusText() {
    if (isOnline.value) {
      switch (lastResult.value) {
        case ConnectivityResult.wifi:
          return 'متصل بـ WiFi';
        case ConnectivityResult.mobile:
          return 'متصل بشبكة الجوال';
        case ConnectivityResult.ethernet:
          return 'متصل بـ Ethernet';
        default:
          return 'متصل';
      }
    } else {
      return 'غير متصل بالإنترنت';
    }
  }
  
  /// Dispose monitor
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}

/// Upload recovery manager for handling offline uploads
class OfflineUploadRecovery {
  static final OfflineUploadRecovery _instance = OfflineUploadRecovery._internal();
  
  factory OfflineUploadRecovery() {
    return _instance;
  }
  
  OfflineUploadRecovery._internal();
  
  final BackgroundUploadService _uploadService = BackgroundUploadService();
  final ConnectivityMonitor _connectivityMonitor = ConnectivityMonitor();
  
  final RxMap<String, OfflineUploadState> _uploadStates =
      <String, OfflineUploadState>{}.obs;
  
  /// Initialize offline recovery
  Future<void> initialize() async {
    try {
      await _connectivityMonitor.initialize();
      debugPrint('✅ [OfflineUploadRecovery] Initialized');
    } catch (e, st) {
      debugPrint('❌ [OfflineUploadRecovery] Initialization failed: $e');
      debugPrint('❌ [OfflineUploadRecovery] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Handle upload during offline
  Future<void> handleOfflineUpload({
    required String messageId,
    required String chatId,
    required String userId,
    required String localFilePath,
    required String uploadPath,
    required String mediaType,
  }) async {
    try {
      // Add to upload service (will queue if offline)
      await _uploadService.addUpload(
        messageId: messageId,
        chatId: chatId,
        userId: userId,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        mediaType: mediaType,
      );
      
      // Track state
      _uploadStates[messageId] = OfflineUploadState(
        messageId: messageId,
        chatId: chatId,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        mediaType: mediaType,
        addedAt: DateTime.now(),
        isOnline: _connectivityMonitor.isOnline.value,
        retryCount: 0,
      );
      
      debugPrint('💾 [OfflineUploadRecovery] Upload queued: $messageId');
    } catch (e, st) {
      debugPrint('❌ [OfflineUploadRecovery] Failed to queue upload: $e');
      debugPrint('❌ [OfflineUploadRecovery] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Get recovery state for message
  OfflineUploadState? getRecoveryState(String messageId) {
    return _uploadStates[messageId];
  }
  
  /// Check if message is queued for offline upload
  bool isQueuedForOffline(String messageId) {
    return _uploadStates.containsKey(messageId);
  }
  
  /// Get pending offline uploads
  List<OfflineUploadState> getPendingOfflineUploads() {
    return _uploadStates.values.toList();
  }
  
  /// Mark upload as recovered
  void markAsRecovered(String messageId) {
    final state = _uploadStates[messageId];
    if (state != null) {
      state.recoveredAt = DateTime.now();
      debugPrint('✅ [OfflineUploadRecovery] Upload recovered: $messageId');
    }
  }
  
  /// Mark upload as failed after offline recovery
  void markAsFailed(String messageId, String reason) {
    final state = _uploadStates[messageId];
    if (state != null) {
      state.lastErrorReason = reason;
      state.retryCount++;
      debugPrint('❌ [OfflineUploadRecovery] Upload failed: $messageId ($reason)');
    }
  }
  
  /// Get connectivity status
  bool get isOnline => _connectivityMonitor.isOnline.value;
  
  /// Get connectivity monitor
  ConnectivityMonitor get connectivityMonitor => _connectivityMonitor;
  
  /// Dispose recovery
  void dispose() {
    _connectivityMonitor.dispose();
  }
}

/// Offline upload state tracking
class OfflineUploadState {
  final String messageId;
  final String chatId;
  final String localFilePath;
  final String uploadPath;
  final String mediaType;
  final DateTime addedAt;
  bool isOnline;
  int retryCount;
  DateTime? recoveredAt;
  String? lastErrorReason;
  
  OfflineUploadState({
    required this.messageId,
    required this.chatId,
    required this.localFilePath,
    required this.uploadPath,
    required this.mediaType,
    required this.addedAt,
    required this.isOnline,
    required this.retryCount,
    this.recoveredAt,
    this.lastErrorReason,
  });
  
  /// Check if upload is still pending
  bool get isPending => recoveredAt == null;
  
  /// Check if upload was recovered
  bool get wasRecovered => recoveredAt != null && lastErrorReason == null;
  
  /// Get time pending in queue
  Duration get timePending => DateTime.now().difference(addedAt);
  
  @override
  String toString() {
    return 'OfflineUploadState(messageId: $messageId, pending: $isPending, recovered: $wasRecovered)';
  }
}
