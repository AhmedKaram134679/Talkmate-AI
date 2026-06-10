import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/media_state_model.dart';
import 'package:talkmate_ai/data/services/background_upload_service.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/models/message_model.dart';

/// Service for handling instant media preview and upload
/// Ensures media appears immediately, uploads in background
class InstantPreviewService {
  static final InstantPreviewService _instance = InstantPreviewService._internal();
  
  factory InstantPreviewService() {
    return _instance;
  }
  
  InstantPreviewService._internal();
  
  final BackgroundUploadService _uploadService = BackgroundUploadService();
  
  /// Create message for immediate display with background upload
  /// Message status flow: local -> uploading -> uploaded -> sending -> sent -> delivered -> read
  Future<MessageModel> createInstantPreviewMessage({
    required String chatId,
    required String senderId,
    required String localFilePath,
    required String uploadPath,
    required MessageType messageType,
    String? displayContent,
    String? replyToMessageId,
  }) async {
    try {
      final fileName = localFilePath.split('/').last;
      
      // Step 1: Create message with LOCAL status for immediate display
      final message = MessageModel(
        chatId: chatId,
        senderId: senderId,
        content: displayContent ?? '[${messageType.name.toUpperCase()}]',
        type: messageType,
        status: MessageStatus.local,
        localFilePath: localFilePath,
        replyToMessageId: replyToMessageId,
        userReactions: {
          'originalFileName': fileName,
        },
      );
      
      debugPrint('📱 [InstantPreviewService] Created instant preview: ${message.id}');
      
      // Initialize Media State Store with LOCAL status
      await MediaStateStore.to.updateState(MediaState(
        messageId: message.id,
        localPath: localFilePath,
        uploadStatus: MediaUploadStatus.local,
      ));

      // Step 2: Validate file exists
      if (!File(localFilePath).existsSync()) {
        throw Exception('File not found: $localFilePath');
      }
      
      // Step 3: Queue upload in background (independent of UI)
      // This happens asynchronously without blocking message display
      _queueBackgroundUpload(
        message: message,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        fileName: fileName,
      ).ignore();
      
      return message;
    } catch (e, st) {
      debugPrint('❌ [InstantPreviewService] Failed to create preview: $e');
      debugPrint('❌ [InstantPreviewService] Stacktrace: $st');
      rethrow;
    }
  }
  
  /// Queue background upload without blocking UI
  Future<void> _queueBackgroundUpload({
    required MessageModel message,
    required String localFilePath,
    required String uploadPath,
    String? fileName,
  }) async {
    try {
      // Small delay to ensure message is rendered first
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Add to background upload service
      // This returns immediately; upload happens in background
      _uploadService.addUpload(
        messageId: message.id,
        chatId: message.chatId,
        userId: message.senderId,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        mediaType: message.type.name,
        fileName: fileName,
      ).ignore();
      
      debugPrint('📤 [InstantPreviewService] Upload queued for: ${message.id}');
    } catch (e, st) {
      debugPrint('⚠️ [InstantPreviewService] Upload queueing error: $e');
      debugPrint('⚠️ [InstantPreviewService] Stacktrace: $st');
    }
  }
  
  /// Convert local message to uploading state
  MessageModel toUploadingState(MessageModel message) {
    return message.copyWith(
      status: MessageStatus.uploading,
    );
  }
  
  /// Convert local message to uploaded state
  MessageModel toUploadedState(MessageModel message) {
    return message.copyWith(
      status: MessageStatus.uploaded,
    );
  }
  
  /// Convert local message to sending state
  MessageModel toSendingState(MessageModel message) {
    return message.copyWith(
      status: MessageStatus.pending,
    );
  }
  
  /// Get observable upload progress for message
  RxDouble getUploadProgress(String messageId) {
    return _uploadService.getUploadProgressObservable(messageId);
  }
  
  /// Get observable upload status for message
  RxString getUploadStatus(String messageId) {
    return _uploadService.getUploadStatusObservable(messageId);
  }
  
  /// Retry failed upload
  Future<void> retryFailedUpload(String messageId) async {
    await _uploadService.retryUpload(messageId);
  }
  
  /// Cancel upload
  void cancelUpload(String messageId) {
    _uploadService.cancelUpload(messageId);
  }
}
