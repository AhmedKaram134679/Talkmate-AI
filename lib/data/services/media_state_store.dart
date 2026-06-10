import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/media_state_model.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';
import 'package:talkmate_ai/models/message_model.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

/// Unified Media State Store - The Single Source of Truth for media lifecycle
class MediaStateStore extends GetxService {
  static MediaStateStore get to => Get.find();

  final SqliteDatabaseService _db = SqliteDatabaseService();

  // Observable map for real-time UI updates
  // Key: messageId, Value: MediaState
  final RxMap<String, MediaState> _states = <String, MediaState>{}.obs;

  // Write serialization: per-message Completer queue to prevent concurrent writes
  final Map<String, Completer<void>> _writeQueues = {};

  /// Initialize the store by loading all states from SQLite
  Future<MediaStateStore> init() async {
    try {
      debugPrint('🚀 [MediaStateStore] Initializing...');
      final storedStates = await _db.getAllMediaStates();

      for (final map in storedStates) {
        try {
          final state = MediaState.fromMap(map);
          _states[state.messageId] = state;
          
          ForensicLogger.log(
            tag: 'VIDEO_STATE_RESTORED',
            messageId: state.messageId,
            localId: state.messageId,
            taskId: state.uploadTaskId,
            filename: state.fileName,
            localFilePath: state.localPath,
            thumbnailPath: state.thumbnailPath,
            remoteUrl: state.remoteUrl,
            status: state.uploadStatus.name,
            uploadProgress: state.lastKnownProgress,
          );
        } catch (e) {
          debugPrint(
              '⚠️ [MediaStateStore] Failed to load state for message: ${map['message_id']}, error: $e');
        }
      }

      debugPrint(
          '✅ [MediaStateStore] Initialized with ${_states.length} media states');
      return this;
    } catch (e) {
      debugPrint('❌ [MediaStateStore] Initialization failed: $e');
      return this;
    }
  }

  /// The ONLY authority for media resolution in the UI layer.
  /// If state is missing, returns a fallback ResolvedMedia (not available).
  ResolvedMedia resolve(String messageId) {
    debugPrint(
        '🔍 [MediaStateStore] MEDIA_RESOLVE_START: messageId=$messageId');

    final state = _states[messageId];

    if (state == null) {
      debugPrint(
          '⚠️ [MediaStateStore] MEDIA_STATE_FALLBACK_USED: No state found for $messageId');
      return ResolvedMedia(
        messageId: messageId,
        status: MediaUploadStatus.failed,
        progress: 0.0,
        isAvailable: false,
        errorMessage: 'Media state missing',
      );
    }

    return _resolveFromState(state);
  }

  /// Resolve media for a specific message, seeding state if missing.
  /// This is the PRIMARY resolution method for the UI layer.
  /// If no state exists but the message has media data, seeds state from message.
  ResolvedMedia resolveForMessage(String messageId, {MessageModel? message}) {
    debugPrint(
        '🔍 [MediaStateStore] MEDIA_RESOLVE_START: messageId=$messageId (with message context)');

    final state = _states[messageId];

    if (state != null) {
      return _resolveFromState(state);
    }

    // No state found - attempt to seed from message data
    if (message != null && _isMediaMessage(message)) {
      debugPrint(
          '🌱 [MediaStateStore] MEDIA_STATE_SEEDED: messageId=$messageId (seeded from message)');
      // Synchronous seed to in-memory map (persist async in background)
      final seededState = _buildStateFromMessage(message);
      _states[messageId] = seededState;
      // Persist asynchronously - don't await
      _db.saveMediaState(seededState.toMap());
      return _resolveFromState(seededState);
    }

    debugPrint(
        '⚠️ [MediaStateStore] MEDIA_STATE_FALLBACK_USED: No state and no message context for $messageId');
    return ResolvedMedia(
      messageId: messageId,
      status: MediaUploadStatus.failed,
      progress: 0.0,
      isAvailable: false,
      errorMessage: 'Media state missing',
    );
  }

  /// Seed a MediaState from a MessageModel.
  /// Called when a media message is first encountered or during batch rebuild.
  Future<void> seedFromMessage(MessageModel message) async {
    final messageId = message.id;
    if (_states.containsKey(messageId)) return; // Already seeded
    if (!_isMediaMessage(message)) return;

    final state = _buildStateFromMessage(message);
    _states[messageId] = state;
    await _db.saveMediaState(state.toMap());
    debugPrint(
        '🌱 [MediaStateStore] MEDIA_STATE_SEEDED: messageId=$messageId, status=${state.uploadStatus.name}');
  }

  /// Rebuild the in-memory index from a list of messages.
  /// Seeds any missing media states from message data.
  /// Call this after initial message load to ensure all media has state.
  Future<void> rebuildIndex(List<MessageModel> messages) async {
    int seededCount = 0;
    for (final message in messages) {
      if (!_isMediaMessage(message)) continue;
      if (_states.containsKey(message.id)) continue;

      final state = _buildStateFromMessage(message);
      _states[message.id] = state;
      // Persist in background
      unawaited(_db.saveMediaState(state.toMap()));
      seededCount++;
    }
    if (seededCount > 0) {
      debugPrint(
          '🔄 [MediaStateStore] rebuildIndex: Seeded $seededCount missing media states from ${messages.length} messages');
    }
  }

  /// Build ResolvedMedia from a known state
  ResolvedMedia _resolveFromState(MediaState state) {
    debugPrint(
        '✅ [MediaStateStore] MEDIA_STATE_FOUND: messageId=${state.messageId}, status=${state.uploadStatus.name}');

    final localFileExists =
        state.localPath != null && File(state.localPath!).existsSync();
    final isAvailable = localFileExists || state.remoteUrl != null;

    // Priority: state.fileName > extracted from localPath > extracted from remoteUrl
    final fileName = state.fileName ??
        state.localPath?.split(Platform.pathSeparator).last ??
        (state.remoteUrl != null
            ? _extractFileNameFromUrl(state.remoteUrl!)
            : null);

    final resolved = ResolvedMedia(
      messageId: state.messageId,
      localPath: state.localPath,
      remoteUrl: state.remoteUrl,
      fileName: fileName,
      status: state.uploadStatus,
      progress: state.lastKnownProgress,
      isAvailable: isAvailable,
      errorMessage: state.errorMessage,
      hasLocalFile: localFileExists,
      mediaType: state.mediaType,
      thumbnailPath: state.thumbnailPath,
      remoteThumbnailUrl: state.remoteThumbnailUrl,
    );

    debugPrint(
        '🎬 [MediaStateStore] MEDIA_RENDER_SOURCE: messageId=${state.messageId}, source=${localFileExists ? "LOCAL" : (state.remoteUrl != null ? "REMOTE" : "NONE")}');

    return resolved;
  }

  /// Check if a message is a media type
  bool _isMediaMessage(MessageModel message) {
    return message.isImageMessage ||
        message.isVideoMessage ||
        message.isFileMessage ||
        message.isAudioMessage;
  }

  /// Build a MediaState from a MessageModel's available data
  MediaState _buildStateFromMessage(MessageModel message) {
    // Determine media URL from metadata
    final mediaUrl = message.metadata?['mediaUrl'] as String?;
    final localPath = message.localFilePath;

    // CRITICAL: Get fileName with priority order (VIDEO_TRACE_MEDIA_STATE_SAVE)
    // Priority: message.originalFileName > reactions > metadata > extract from URL/path > null
    final fileName = message.originalFileName ??
        message.userReactions['originalFileName'] ??
        message.userReactions['filename'] ??
        message.metadata?['originalFileName'] ??
        message.metadata?['filename'] ??
        (mediaUrl != null ? _extractFileNameFromUrl(mediaUrl) : null) ??
        localPath?.split(Platform.pathSeparator).last;

    // Determine upload status from message status
    MediaUploadStatus uploadStatus;
    switch (message.status) {
      case MessageStatus.local:
      case MessageStatus.pending:
        uploadStatus = MediaUploadStatus.local;
        break;
      case MessageStatus.uploading:
        uploadStatus = MediaUploadStatus.uploading;
        break;
      case MessageStatus.uploaded:
        uploadStatus = MediaUploadStatus.uploaded;
        break;
      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        uploadStatus = mediaUrl != null
            ? MediaUploadStatus.synced
            : MediaUploadStatus.uploaded;
        break;
      case MessageStatus.failed:
        uploadStatus = MediaUploadStatus.failed;
        break;
    }

    // Map message type to media type string
    String mediaType;
    if (message.isImageMessage) {
      mediaType = 'image';
    } else if (message.isVideoMessage) {
      mediaType = 'video';
    } else if (message.isAudioMessage) {
      mediaType = 'audio';
    } else {
      mediaType = 'file';
    }

    final state = MediaState(
      messageId: message.id,
      localPath: localPath,
      remoteUrl: mediaUrl,
      uploadStatus: uploadStatus,
      lastKnownProgress: message.uploadProgress,
      fileName: fileName,
      mediaType: mediaType,
      errorMessage: message.isFailed ? 'Upload failed' : null,
      thumbnailPath: message.localThumbnailPath ?? (message.metadata?['thumbnailPath'] as String?),
      remoteThumbnailUrl: message.metadata?['thumbnailUrl'] as String?,
    );
    
    debugPrint('VIDEO_TRACE_MEDIA_STATE_SAVE: messageId=${message.id}, fileName=$fileName, filePath=$localPath, status=${uploadStatus.name}, mediaType=$mediaType');
    
    return state;
  }

  /// Extract filename from a URL
  String _extractFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty && segments.last.isNotEmpty) {
        return Uri.decodeComponent(segments.last);
      }
      return url.split('/').last;
    } catch (_) {
      return url.split('/').last;
    }
  }

  /// Get observable state for a message
  Rx<MediaState>? getStateObservable(String messageId) {
    if (!_states.containsKey(messageId)) return null;
    return Rx(_states[messageId]!);
  }

  /// Get current state for a message
  MediaState? getState(String messageId) {
    return _states[messageId];
  }

  /// Update media state and persist to SQLite (SERIALIZED per messageId)
  /// Concurrent writes for the same messageId are queued to prevent race conditions
  Future<void> updateState(MediaState newState) async {
    // Update in-memory state immediately (synchronous for UI responsiveness)
    _states[newState.messageId] = newState;

    // Serialize writes per messageId to prevent SQLite race conditions
    final messageId = newState.messageId;
    final previousCompleter = _writeQueues[messageId];

    // Create a completer for this write operation
    final completer = Completer<void>();
    _writeQueues[messageId] = completer;

    try {
      // Wait for any previous write to complete
      if (previousCompleter != null) {
        await previousCompleter.future;
      }

      // Persist to SQLite
      await _db.saveMediaState(newState.toMap());
      debugPrint(
          '💾 [MediaStateStore] State updated: ${newState.messageId} -> ${newState.uploadStatus.name}');
    } catch (e) {
      debugPrint(
          '❌ [MediaStateStore] State persist failed: ${newState.messageId}, error: $e');
    } finally {
      completer.complete();
      // Clean up queue if this is still the current completer
      if (identical(_writeQueues[messageId], completer)) {
        _writeQueues.remove(messageId);
      }
    }
  }

  /// Partial update helper
  Future<void> updatePartial(
    String messageId, {
    String? localPath,
    String? remoteUrl,
    MediaUploadStatus? uploadStatus,
    String? uploadTaskId,
    double? progress,
    String? errorMessage,
    String? fileName,
    String? mediaType,
  }) async {
    final currentState = _states[messageId] ?? MediaState(messageId: messageId);

    final updatedState = currentState.copyWith(
      localPath: localPath,
      remoteUrl: remoteUrl,
      uploadStatus: uploadStatus,
      uploadTaskId: uploadTaskId,
      lastKnownProgress: progress,
      errorMessage: errorMessage,
      fileName: fileName,
      mediaType: mediaType,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await updateState(updatedState);
  }

  /// Delete media state
  Future<void> deleteState(String messageId) async {
    _states.remove(messageId);
    await _db.deleteMediaState(messageId);
    debugPrint('🗑️ [MediaStateStore] State deleted: $messageId');
  }

  /// Reactive access to all states
  Map<String, MediaState> get allStates => _states;

  /// Stream of state changes for the entire store
  Stream<Map<String, MediaState>> get statesStream => _states.stream;
}
