import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/media_state_model.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';
import 'package:talkmate_ai/data/services/upload_manager.dart';

/// Manages upload failure recovery and retry logic
class UploadRecoveryManager {
  static final UploadRecoveryManager _instance = UploadRecoveryManager._internal();
  
  factory UploadRecoveryManager() {
    return _instance;
  }
  
  UploadRecoveryManager._internal();
  
  final SqliteDatabaseService _db = SqliteDatabaseService();
  final UploadManager _uploadManager = UploadManager();
  final RxMap<String, FailureRecoveryState> _recoveryStates = 
      <String, FailureRecoveryState>{}.obs;
  
  /// Initialize recovery manager
  Future<void> initialize() async {
    try {
      // Restore failed uploads from database to populate UI state
      final failedUploads = await _db.getFailedUploads();
      for (final row in failedUploads) {
        final messageId = row['message_id'] as String;
        _recoveryStates[messageId] = FailureRecoveryState(
          messageId: messageId,
          failureReason: row['failure_reason'] as String? ?? 'Unknown error',
          errorMessage: row['failure_reason'] as String? ?? 'Failed to upload',
        );
      }
      debugPrint('✅ [UploadRecoveryManager] Initialized with ${_recoveryStates.length} failed uploads');
    } catch (e, st) {
      debugPrint('❌ [UploadRecoveryManager] Initialization failed: $e');
      debugPrint('❌ [UploadRecoveryManager] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Handle upload failure
  Future<void> handleUploadFailure({
    required String messageId,
    required String failureReason,
    required String errorMessage,
  }) async {
    try {
      final recovery = FailureRecoveryState(
        messageId: messageId,
        failureReason: failureReason,
        errorMessage: errorMessage,
      );
      
      _recoveryStates[messageId] = recovery;
      
      // Update Unified Media State Store
      await MediaStateStore.to.updatePartial(
        messageId,
        uploadStatus: MediaUploadStatus.failed,
        errorMessage: errorMessage,
      );
      
      await _db.insertFailedUpload(
        id: messageId,
        messageId: messageId,
        filePath: '',
        failureReason: failureReason,
      );
      
      debugPrint('⚠️ [UploadRecoveryManager] Upload failure recorded: $messageId');
    } catch (e, st) {
      debugPrint('❌ [UploadRecoveryManager] Failed to handle upload failure: $e');
      debugPrint('❌ [UploadRecoveryManager] Stacktrace: $st');
    }
  }
  
  /// Get recovery state for message
  FailureRecoveryState? getRecoveryState(String messageId) {
    return _recoveryStates[messageId];
  }
  
  /// Check if message has failed upload
  bool hasFailedUpload(String messageId) {
    return _recoveryStates.containsKey(messageId);
  }
  
  /// Get user-friendly error message
  String getUserFriendlyErrorMessage(String messageId) {
    final recovery = _recoveryStates[messageId];
    if (recovery == null) return 'فشل الرفع';
    
    if (recovery.errorMessage.contains('timeout')) {
      return 'انتهت مهلة الاتصال - تحقق من الإنترنت';
    } else if (recovery.errorMessage.contains('404')) {
      return 'لم يتم العثور على الملف';
    } else if (recovery.errorMessage.contains('413')) {
      return 'الملف كبير جداً';
    } else if (recovery.errorMessage.contains('401') || 
               recovery.errorMessage.contains('403')) {
      return 'خطأ في التصريح - حاول تسجيل الدخول مجدداً';
    } else {
      return 'فشل الرفع: ${recovery.errorMessage}';
    }
  }
  
  /// Retry upload manually
  Future<void> retryUpload(String messageId) async {
    try {
      final recovery = _recoveryStates[messageId];
      if (recovery == null) {
        debugPrint('⚠️ [UploadRecoveryManager] No recovery state for: $messageId');
        return;
      }
      
      // Decrement retry count
      await _db.decrementFailedUploadRetries(messageId);
      recovery.attemptCount++;
      recovery.lastRetryAt = DateTime.now();
      
      await _uploadManager.retryUpload(messageId);
      
      debugPrint('🔄 [UploadRecoveryManager] Retry initiated: $messageId (Attempt ${recovery.attemptCount})');
    } catch (e, st) {
      debugPrint('❌ [UploadRecoveryManager] Retry failed: $e');
      debugPrint('❌ [UploadRecoveryManager] Stacktrace: $st');
    }
  }
  
  /// Cancel upload (remove from failed)
  Future<void> cancelUpload(String messageId) async {
    try {
      await _db.deleteFailedUpload(messageId);
      _recoveryStates.remove(messageId);
      
      debugPrint('🛑 [UploadRecoveryManager] Upload cancelled: $messageId');
    } catch (e, st) {
      debugPrint('❌ [UploadRecoveryManager] Cancel failed: $e');
      debugPrint('❌ [UploadRecoveryManager] Stacktrace: $st');
    }
  }
  
  /// Delete message with failed upload
  Future<void> deleteMessage(String messageId) async {
    try {
      await _db.deleteFailedUpload(messageId);
      _recoveryStates.remove(messageId);
      
      debugPrint('🗑️ [UploadRecoveryManager] Message deleted: $messageId');
    } catch (e, st) {
      debugPrint('❌ [UploadRecoveryManager] Delete failed: $e');
      debugPrint('❌ [UploadRecoveryManager] Stacktrace: $st');
    }
  }
  
  /// Get all failed uploads
  List<String> getAllFailedUploads() {
    return _recoveryStates.keys.toList();
  }
  
  /// Dispose resources
  void dispose() {
    _recoveryStates.clear();
  }
}

/// Represents recovery state for a failed upload
class FailureRecoveryState {
  final String messageId;
  final String failureReason;
  final String errorMessage;
  int attemptCount = 0;
  DateTime? lastRetryAt;
  
  FailureRecoveryState({
    required this.messageId,
    required this.failureReason,
    required this.errorMessage,
  });
  
  @override
  String toString() {
    return 'FailureRecoveryState(messageId: $messageId, reason: $failureReason, attempts: $attemptCount)';
  }
}
