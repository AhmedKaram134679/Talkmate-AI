import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/data/models/media_state_model.dart';
import 'package:talkmate_ai/data/models/upload_task_model.dart';
import 'package:talkmate_ai/data/services/chat_sync_engine.dart';
import 'package:talkmate_ai/data/services/database_service_native.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';
import 'package:talkmate_ai/data/services/storage_service.dart';
import 'package:talkmate_ai/data/services/upload_queue.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

/// Main upload manager - orchestrates all upload operations
class UploadManager {
  static final UploadManager _instance = UploadManager._internal();

  factory UploadManager() {
    return _instance;
  }

  UploadManager._internal();

  final UploadQueue _queue = UploadQueue();
  final SqliteDatabaseService _db = SqliteDatabaseService();

  Timer? _retryTimer;
  bool _isProcessing = false;

  // Callbacks for UI updates
  final RxMap<String, RxDouble> uploadProgressMap = <String, RxDouble>{}.obs;
  final RxMap<String, RxString> uploadStatusMap = <String, RxString>{}.obs;

  /// Initialize upload manager
  Future<void> initialize() async {
    try {
      // Restore pending uploads from database
      await _restorePendingUploads();
      debugPrint(
          '✅ [UploadManager] Initialized with ${_queue.size} pending tasks');
    } catch (e, st) {
      debugPrint('❌ [UploadManager] Initialization failed: $e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
      rethrow;
    }
  }

  /// Add new upload task
  Future<UploadTask> addUpload({
    required String messageId,
    required String chatId,
    required String userId,
    required String localFilePath,
    required String uploadPath,
    required String mediaType,
    String? fileName,
    UploadPriority priority = UploadPriority.normal,
  }) async {
    try {
      final file = File(localFilePath);
      if (!file.existsSync()) {
        debugPrint(
            '⚠️ [UploadManager] UPLOAD_TASK_INVALID: File not found at $localFilePath');
      }
      final fileSize = await file.length();

      // Use original filename if provided, otherwise extract from path
      final effectiveFileName = fileName ?? localFilePath.split('/').last;

      final task = UploadTask(
        taskId: '${messageId}_${DateTime.now().millisecondsSinceEpoch}',
        messageId: messageId,
        chatId: chatId,
        userId: userId,
        localFilePath: localFilePath,
        uploadPath: uploadPath,
        mediaType: mediaType,
        fileSizeBytes: fileSize,
      );

      debugPrint(
          'VIDEO_TRACE_QUEUE_ADD: messageId=$messageId, taskId=${task.taskId}, fileName=$effectiveFileName, filePath=$localFilePath, status=queued, mediaType=$mediaType');

      // Update Unified Media State Store
      await MediaStateStore.to.updatePartial(
        messageId,
        localPath: localFilePath,
        uploadStatus: MediaUploadStatus.queued,
        uploadTaskId: task.taskId,
      );

      // Add to queue
      _queue.enqueue(task, priority: priority);

      // Persist to database (using SqliteDatabaseService)
      await _db.insertPendingUpload(
        id: task.taskId,
        messageId: messageId,
        filePath: localFilePath,
        fileName: effectiveFileName,
        fileSize: fileSize.toInt(),
        mediaType: mediaType,
        chatId: chatId,
        userId: userId,
        uploadPath: uploadPath,
      );

      // Log VIDEO_TASK_PERSISTED
      ForensicLogger.log(
        tag: 'VIDEO_TASK_PERSISTED',
        messageId: messageId,
        localId: messageId,
        chatId: chatId,
        taskId: task.taskId,
        filename: effectiveFileName,
        localFilePath: localFilePath,
        thumbnailPath: MediaStateStore.to.getState(messageId)?.thumbnailPath,
        status: 'persisted',
        uploadProgress: 0.0,
      );

      // Initialize progress tracking
      uploadProgressMap[messageId] = RxDouble(0.0);
      uploadStatusMap[messageId] = RxString('pending');

      processQueue().ignore();
      return task;
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] UPLOAD_TASK_FAILED: messageId=$messageId, error=$e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
      rethrow;
    }
  }

  /// Process upload queue
  Future<void> processQueue() async {
    if (_isProcessing || _queue.isEmpty) {
      if (_isProcessing) {
        debugPrint(
            '⏳ [UploadManager] UPLOAD_WORKER_BUSY: Processing already in progress');
      }
      return;
    }

    _isProcessing = true;
    debugPrint(
        '⚙️ [UploadManager] UPLOAD_WORKER_STARTED: Processing ${_queue.size} tasks');

    try {
      while (!_queue.isEmpty) {
        final task = _queue.dequeue();
        if (task == null) break;

        debugPrint(
            '🎯 [UploadManager] UPLOAD_WORKER_PICKED_TASK: taskId=${task.taskId}, messageId=${task.messageId}, fileName=${task.localFilePath.split('/').last}, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}');
        await _executeUpload(task);
      }
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] UPLOAD_WORKER_ERROR: Critical failure in process loop: $e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    } finally {
      debugPrint('🏁 [UploadManager] UPLOAD_WORKER_FINISHED');
      _isProcessing = false;
    }
  }

  /// Execute single upload
  Future<void> _executeUpload(UploadTask task) async {
    final fileName = task.localFilePath.split('/').last;
    final mediaState = MediaStateStore.to.getState(task.messageId);
    final localThumbnailPath = mediaState?.thumbnailPath;
    String? remoteThumbnailUrl = mediaState?.remoteThumbnailUrl;

    try {
      task.status = UploadTaskStatus.uploading;
      task.lastAttemptAt = DateTime.now();
      task.attemptCount++;

      uploadStatusMap[task.messageId]?.value = 'uploading';

      debugPrint(
          '📤 [UploadManager] UPLOAD_STORAGE_START: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount - 1}');

      // Log VIDEO_UPLOAD_RESUMED
      ForensicLogger.log(
        tag: 'VIDEO_UPLOAD_RESUMED',
        messageId: task.messageId,
        localId: task.messageId,
        chatId: task.chatId,
        taskId: task.taskId,
        filename: fileName,
        localFilePath: task.localFilePath,
        thumbnailPath: localThumbnailPath,
        remoteUrl: task.uploadedUrl,
        status: 'uploading',
        uploadProgress: task.progress,
      );

      // Check if this task is a video and has a local thumbnail that needs uploading
      if (task.mediaType == 'video' && localThumbnailPath != null && remoteThumbnailUrl == null) {
        final thumbFile = File(localThumbnailPath);
        if (thumbFile.existsSync()) {
          debugPrint('📸 [UploadManager] Video thumbnail upload starting: $localThumbnailPath');
          final thumbRemotePath = 'chats/${task.chatId}/users/${task.userId}/thumbnails/${task.messageId}_thumb.jpg';
          try {
            final (uploadedThumbUrl, _) = await StorageService.instance.uploadFile(
              file: XFile(localThumbnailPath),
              path: thumbRemotePath,
              logContext: {
                'taskId': task.taskId,
                'messageId': task.messageId,
                'originalFileName': '${task.messageId}_thumb.jpg',
                'fileName': '${task.messageId}_thumb.jpg',
                'localPath': localThumbnailPath,
                'currentStatus': 'uploading',
                'retryCount': task.attemptCount,
              },
            );
            remoteThumbnailUrl = uploadedThumbUrl;
            
            // Save remoteThumbnailUrl in MediaStateStore
            if (mediaState != null) {
              await MediaStateStore.to.updateState(mediaState.copyWith(
                remoteThumbnailUrl: uploadedThumbUrl,
              ));
            }
            
            // Also update local_messages table metadata to store the thumbnailUrl so it is synced
            await _updateLocalMessageThumbnail(task.messageId, uploadedThumbUrl);
            debugPrint('✅ [UploadManager] Video thumbnail uploaded successfully: $uploadedThumbUrl');
          } catch (e) {
            debugPrint('⚠️ [UploadManager] Video thumbnail upload failed (continuing with video upload): $e');
          }
        }
      }

      // Update database status to uploading
      await _db.updateUploadStatus(task.taskId, 'uploading');
      await MediaStateStore.to.updatePartial(
        task.messageId,
        uploadStatus: MediaUploadStatus.uploading,
        progress: 0.0,
      );
      await _updateLocalMessageProgress(task.messageId, 0.0);

      // Read file
      final file = File(task.localFilePath);
      if (!file.existsSync()) {
        debugPrint(
            '❌ [UploadManager] UPLOAD_STORAGE_FAILED: File missing at ${task.localFilePath}');
        throw Exception('File not found: ${task.localFilePath}');
      }

      // Upload to storage
      try {
        // Use direct file upload to avoid reading all bytes into memory (prevents OOM crashes)
        final (url, size) = await StorageService.instance.uploadFileDirect(
          file: file,
          path: task.uploadPath,
          logContext: {
            'taskId': task.taskId,
            'messageId': task.messageId,
            'originalFileName': mediaState?.fileName ?? task.localFilePath.split('/').last,
            'fileName': fileName,
            'fileSize': task.fileSizeBytes,
            'localPath': task.localFilePath,
            'currentStatus': task.status.name,
            'retryCount': task.attemptCount,
          },
          onProgress: (progress) {
            task.progress = progress;
            uploadProgressMap[task.messageId]?.value = progress;

            // Log UPLOAD_PROGRESS
            ForensicLogger.log(
              tag: 'UPLOAD_PROGRESS',
              messageId: task.messageId,
              localId: task.messageId,
              chatId: task.chatId,
              taskId: task.taskId,
              filename: fileName,
              localFilePath: task.localFilePath,
              thumbnailPath: localThumbnailPath,
              status: 'uploading',
              uploadProgress: progress,
              extra: 'progress=${(progress * 100).toStringAsFixed(1)}%',
            );

            // THROTTLE: Only persist to SQLite every 5% or at completion (1.0)
            // This prevents write storm (hundreds of writes per upload)
            final shouldPersist = progress >= 1.0 ||
                (progress - (task.lastPersistedProgress ?? 0.0)).abs() >= 0.05;
            if (shouldPersist) {
              task.lastPersistedProgress = progress;
              MediaStateStore.to
                  .updatePartial(
                    task.messageId,
                    progress: progress,
                  )
                  .ignore();
              _updateLocalMessageProgress(task.messageId, progress).ignore();
            }
          },
        );

        task.status = UploadTaskStatus.completed;
        task.uploadedUrl = url;
        task.progress = 1.0;
        uploadProgressMap[task.messageId]?.value = 1.0;
        uploadStatusMap[task.messageId]?.value = 'uploaded';

        // Update Unified Media State Store
        await MediaStateStore.to.updatePartial(
          task.messageId,
          remoteUrl: url,
          uploadStatus: MediaUploadStatus.uploaded,
          progress: 1.0,
        );

        // Update database
        await _db.updateUploadStatus(task.taskId, 'completed');
        await _completeLocalMessageUpload(task.messageId, url, size);

        debugPrint(
            '✅ [UploadManager] UPLOAD_TASK_COMPLETED: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}, url=$url');

        // Log VIDEO_UPLOAD_COMPLETED
        ForensicLogger.log(
          tag: 'VIDEO_UPLOAD_COMPLETED',
          messageId: task.messageId,
          localId: task.messageId,
          chatId: task.chatId,
          taskId: task.taskId,
          filename: fileName,
          localFilePath: task.localFilePath,
          thumbnailPath: localThumbnailPath,
          remoteUrl: url,
          status: 'completed',
          uploadProgress: 1.0,
        );

        // Trigger ChatSyncEngine to send the message remote
        if (Get.isRegistered<ChatSyncEngine>()) {
          Get.find<ChatSyncEngine>().syncPendingMessages().ignore();
        }
      } catch (e, st) {
        debugPrint(
            '❌ [UploadManager] UPLOAD_STORAGE_FAILED: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}, error=$e');
        debugPrint('❌ [UploadManager] Stacktrace: $st');

        // Handle upload failure
        if (task.canRetry()) {
          task.status = UploadTaskStatus.failed;
          task.errorMessage = e.toString();
          uploadStatusMap[task.messageId]?.value = 'failed';

          // Update Unified Media State Store
          await MediaStateStore.to.updatePartial(
            task.messageId,
            uploadStatus: MediaUploadStatus.failed,
            errorMessage: e.toString(),
          );

          // Update database retry count
          await _db.incrementRetryCount(task.taskId);

          // Re-queue for retry
          final delay = task.getNextRetryDelay();
          debugPrint(
              '🔄 [UploadManager] UPLOAD_TASK_RETRY: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}, delay=$delay');

          _queue.enqueue(task, priority: UploadPriority.high);
          await Future.delayed(delay);
        } else {
          task.status = UploadTaskStatus.failed;
          task.errorMessage = e.toString();
          uploadStatusMap[task.messageId]?.value = 'failed';

          // Update Unified Media State Store
          await MediaStateStore.to.updatePartial(
            task.messageId,
            uploadStatus: MediaUploadStatus.failed,
            errorMessage: e.toString(),
          );

          // Add to failed uploads (using SqliteDatabaseService)
          await _db.insertFailedUpload(
            id: task.taskId,
            messageId: task.messageId,
            filePath: task.localFilePath,
            failureReason: e.toString(),
            chatId: task.chatId,
            userId: task.userId,
            uploadPath: task.uploadPath,
            mediaType: task.mediaType,
          );

          // Remove from pending
          await _db.deletePendingUpload(task.taskId);
          await _failLocalMessageUpload(task.messageId);

          debugPrint(
              '❌ [UploadManager] UPLOAD_TASK_ABORTED: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}, maxRetriesReached');

          // Log VIDEO_UPLOAD_FAILED
          ForensicLogger.log(
            tag: 'VIDEO_UPLOAD_FAILED',
            messageId: task.messageId,
            localId: task.messageId,
            chatId: task.chatId,
            taskId: task.taskId,
            filename: fileName,
            localFilePath: task.localFilePath,
            thumbnailPath: localThumbnailPath,
            status: 'failed',
            uploadProgress: task.progress,
            extra: 'error=$e',
          );
        }
      }
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] UPLOAD_CRITICAL_ERROR: taskId=${task.taskId}, messageId=${task.messageId}, fileName=$fileName, fileSize=${task.fileSizeBytes}, localPath=${task.localFilePath}, currentStatus=${task.status}, retryCount=${task.attemptCount}, error=$e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
      task.status = UploadTaskStatus.failed;
      task.errorMessage = e.toString();
      uploadStatusMap[task.messageId]?.value = 'failed';
      await _failLocalMessageUpload(task.messageId);

      // Log VIDEO_UPLOAD_FAILED
      ForensicLogger.log(
        tag: 'VIDEO_UPLOAD_FAILED',
        messageId: task.messageId,
        localId: task.messageId,
        chatId: task.chatId,
        taskId: task.taskId,
        filename: fileName,
        localFilePath: task.localFilePath,
        thumbnailPath: localThumbnailPath,
        status: 'failed',
        uploadProgress: task.progress,
        extra: 'error=$e',
      );
    }
  }

  /// Restore pending uploads from database
  Future<void> _restorePendingUploads() async {
    try {
      debugPrint('♻️ [UploadManager] UPLOAD_RESTORE_BEGIN');
      final pendingList = await _db.getPendingUploads();
      debugPrint(
          '♻️ [UploadManager] UPLOAD_RESTORE_DB_PULL: found ${pendingList.length} records');

      for (final row in pendingList) {
        final taskId = row['id'] as String;
        final messageId = row['message_id'] as String;
        final chatId = row['chat_id'] as String;
        final userId = row['user_id'] as String;
        final localFilePath = row['file_path'] as String;
        final uploadPath = row['upload_path'] as String;
        final mediaType = row['media_type'] as String;
        final fileSizeBytes = row['file_size'] as int;
        final fileName = row['file_name'] as String?;
        final progressVal = (row['upload_progress'] as num?)?.toDouble() ?? 0.0;

        debugPrint(
            'VIDEO_TRACE_QUEUE_RESTORE: messageId=$messageId, taskId=$taskId, fileName=$fileName, filePath=$localFilePath, status=queued, mediaType=$mediaType');

        var effectiveFilePath = localFilePath;
        var file = File(effectiveFilePath);

        // Auto-healing check: if file is missing, try to find it in documents/media directory
        if (!file.existsSync()) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final mediaDir = Directory(p.join(appDir.path, 'media'));
            if (mediaDir.existsSync()) {
              final files = mediaDir.listSync().whereType<File>();
              final match = files.firstWhereOrNull(
                (f) => p.basenameWithoutExtension(f.path) == messageId,
              );
              if (match != null) {
                effectiveFilePath = match.path;
                file = File(effectiveFilePath);
                debugPrint(
                    '🩹 [UploadManager] UPLOAD_RESTORE_PATH_HEALED: Restored missing path for $messageId to permanent storage: $effectiveFilePath');

                // Persist the healed path in pending_uploads SQLite
                final dbMedia = await _db.database;
                await dbMedia.update(
                  'pending_uploads',
                  {'file_path': effectiveFilePath},
                  where: 'id = ?',
                  whereArgs: [taskId],
                );

                // Persist the healed path in local_messages SQLite
                final dbCore = await DatabaseService.instance.database;
                await dbCore.update(
                  'local_messages',
                  {'local_file_path': effectiveFilePath},
                  where: 'local_id = ?',
                  whereArgs: [messageId],
                );
              }
            }
          } catch (e) {
            debugPrint('⚠️ [UploadManager] Path auto-healing failed: $e');
          }
        }

        if (!file.existsSync()) {
          // DO NOT DELETE: File may be temporarily unavailable (e.g., external storage unmounted)
          // Leave task in DB so it can be retried on next app restart
          debugPrint(
              '⚠️ [UploadManager] UPLOAD_RESTORE_FILE_MISSING: File not found at $effectiveFilePath for taskId=$taskId, messageId=$messageId (task preserved for retry)');
          uploadStatusMap[messageId] = RxString('failed');

          // Log VIDEO_UPLOAD_FAILED since it cannot be resumed
          ForensicLogger.log(
            tag: 'VIDEO_UPLOAD_FAILED',
            messageId: messageId,
            localId: messageId,
            chatId: chatId,
            taskId: taskId,
            filename: fileName,
            localFilePath: effectiveFilePath,
            status: 'failed',
            uploadProgress: progressVal,
            extra: 'file_missing',
          );
          continue;
        }

        // Initialize progress/status tracking in maps
        uploadProgressMap[messageId] = RxDouble(progressVal);
        uploadStatusMap[messageId] = RxString('pending');

        // Update Unified Media State Store for recovery
        await MediaStateStore.to.updatePartial(
          messageId,
          localPath: effectiveFilePath,
          uploadStatus: MediaUploadStatus.queued,
          uploadTaskId: taskId,
          progress: progressVal,
        );

        final mediaState = MediaStateStore.to.getState(messageId);
        final localThumbnailPath = mediaState?.thumbnailPath;

        // Log VIDEO_TASK_RESTORED
        ForensicLogger.log(
          tag: 'VIDEO_TASK_RESTORED',
          messageId: messageId,
          localId: messageId,
          chatId: chatId,
          taskId: taskId,
          filename: fileName,
          localFilePath: effectiveFilePath,
          thumbnailPath: localThumbnailPath,
          status: 'queued',
          uploadProgress: progressVal,
        );

        final task = UploadTask(
          taskId: taskId,
          messageId: messageId,
          chatId: chatId,
          userId: userId,
          localFilePath: effectiveFilePath,
          uploadPath: uploadPath,
          mediaType: mediaType,
          fileSizeBytes: fileSizeBytes,
          progress: progressVal,
          attemptCount: row['retry_count'] as int? ?? 0,
        );

        _queue.enqueue(task);
        debugPrint(
            '♻️ [UploadManager] UPLOAD_RESUME_STARTED: taskId=$taskId, messageId=$messageId');
      }

      debugPrint(
          '✅ [UploadManager] UPLOAD_RESTORE_COMPLETE: count=${_queue.size}');

      if (!_queue.isEmpty) {
        processQueue().ignore();
      }
    } catch (e, st) {
      debugPrint('❌ [UploadManager] UPLOAD_RESTORE_ERROR: $e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    }
  }

  /// Retry failed upload
  Future<void> retryUpload(String messageId) async {
    try {
      final failedUploads = await _db.getFailedUploads();
      final failed = failedUploads.firstWhere(
        (row) => row['message_id'] == messageId || row['id'] == messageId,
        orElse: () => <String, dynamic>{},
      );

      if (failed.isNotEmpty) {
        final localFilePath = failed['file_path'] as String? ?? '';
        final file = File(localFilePath);
        final fileSizeBytes = file.existsSync() ? await file.length() : 0;

        final task = UploadTask(
          taskId: failed['id'] as String? ?? messageId,
          messageId: failed['message_id'] as String? ?? messageId,
          chatId: failed['chat_id'] as String? ?? '',
          userId: failed['user_id'] as String? ?? '',
          localFilePath: localFilePath,
          uploadPath: failed['upload_path'] as String? ?? '',
          mediaType: failed['media_type'] as String? ?? 'unknown',
          fileSizeBytes: fileSizeBytes,
          attemptCount: 0,
        );

        _queue.enqueue(task, priority: UploadPriority.high);
        await _db.deleteFailedUpload(failed['id'] as String? ?? messageId);

        uploadProgressMap[messageId] = RxDouble(0.0);
        uploadStatusMap[messageId] = RxString('uploading');

        processQueue().ignore();
        debugPrint('🔄 [UploadManager] Retry initiated for: $messageId (uploadPath: ${task.uploadPath})');
      }
    } catch (e, st) {
      debugPrint('❌ [UploadManager] Failed to retry upload: $e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    }
  }

  /// Get upload progress for message
  double getUploadProgress(String messageId) {
    return uploadProgressMap[messageId]?.value ?? 0.0;
  }

  /// Get upload status for message
  String getUploadStatus(String messageId) {
    return uploadStatusMap[messageId]?.value ?? 'unknown';
  }

  /// Cancel upload
  void cancelUpload(String messageId) {
    _queue.removeTask(messageId);
    uploadProgressMap.remove(messageId);
    uploadStatusMap.remove(messageId);
    debugPrint('🛑 [UploadManager] Upload cancelled: $messageId');
  }

  /// Get queue status
  Map<String, dynamic> getQueueStatus() {
    return {
      'total': _queue.size,
      'pending': _queue.getPendingTasks().length,
      'processing': _isProcessing,
    };
  }

  final Map<String, int> _lastUpdateMs = {};

  Future<void> _updateLocalMessageProgress(
      String localId, double progress) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastUpdate = _lastUpdateMs[localId] ?? 0;

      // Only update database every 500ms or if progress is 1.0
      if (progress < 1.0 && (now - lastUpdate) < 500) {
        return;
      }

      _lastUpdateMs[localId] = now;

      final db = await DatabaseService.instance.database;

      final List<Map<String, dynamic>> results = await db.query(
        'local_messages',
        columns: ['metadata'],
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (results.isEmpty) {
        debugPrint(
            '⚠️ [UploadManager] DB_UPDATE_SKIPPED: Row not found in local_messages for localId=$localId');
        return;
      }

      Map<String, dynamic> metadataMap = {};
      if (results.first['metadata'] != null) {
        try {
          metadataMap = Map<String, dynamic>.from(
              jsonDecode(results.first['metadata'] as String));
        } catch (e) {
          debugPrint('⚠️ [UploadManager] DB_METADATA_DECODE_FAILED: $e');
        }
      }

      // SELF-HEALING: Restore localFilePath if lost from metadata
      // We can find the task by checking the queue or current processing tasks
      if (!metadataMap.containsKey('localFilePath')) {
        final task = _queue.getTaskByMessageId(localId);
        if (task != null) {
          metadataMap['localFilePath'] = task.localFilePath;
          debugPrint(
              '🩹 [UploadManager] DB_METADATA_HEALED: Restored localFilePath for $localId');
        }
      }

      metadataMap['uploadProgress'] = progress.toString();

      debugPrint(
          '💾 [UploadManager] DB_MESSAGE_STATUS_UPDATE: messageId=$localId, status=uploading, progress=$progress');

      await db.update(
        'local_messages',
        {
          'status': 'uploading',
          'metadata': jsonEncode(metadataMap),
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (Get.isRegistered<ChatController>()) {
        Get.find<ChatController>().chatMessages.refresh();
      }
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] DB_MESSAGE_STATUS_UPDATE_FAILED: messageId=$localId, error=$e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    }
  }

  Future<void> _completeLocalMessageUpload(
      String localId, String url, int size) async {
    try {
      _lastUpdateMs.remove(localId);
      final db = await DatabaseService.instance.database;

      final List<Map<String, dynamic>> results = await db.query(
        'local_messages',
        columns: ['metadata'],
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (results.isEmpty) {
        debugPrint(
            '⚠️ [UploadManager] DB_COMPLETE_SKIPPED: Row not found in local_messages for localId=$localId');
        return;
      }

      Map<String, dynamic> metadataMap = {};
      if (results.first['metadata'] != null) {
        try {
          metadataMap = Map<String, dynamic>.from(
              jsonDecode(results.first['metadata'] as String));
        } catch (e) {
          debugPrint(
              '⚠️ [UploadManager] DB_METADATA_DECODE_FAILED_COMPLETE: $e');
        }
      }

      metadataMap['uploadProgress'] = '1.0';
      metadataMap['mediaUrl'] = url;

      // SELF-HEALING: Restore localFilePath if lost from metadata
      if (!metadataMap.containsKey('localFilePath')) {
        final task = _queue.getTaskByMessageId(localId);
        if (task != null) {
          metadataMap['localFilePath'] = task.localFilePath;
          debugPrint(
              '🩹 [UploadManager] DB_METADATA_HEALED_COMPLETE: Restored localFilePath for $localId');
        }
      }

      debugPrint(
          '💾 [UploadManager] DB_MESSAGE_STATUS_UPDATE: messageId=$localId, status=uploaded, url=$url');

      await db.update(
        'local_messages',
        {
          'status': 'uploaded',
          'media_url': url,
          'media_size': size,
          'metadata': jsonEncode(metadataMap),
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      // Notify ChatController to refresh UI
      if (Get.isRegistered<ChatController>()) {
        Get.find<ChatController>().chatMessages.refresh();
      }
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] DB_MESSAGE_STATUS_UPDATE_FAILED: messageId=$localId, error=$e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    }
  }

  Future<void> _updateLocalMessageThumbnail(String localId, String thumbnailUrl) async {
    try {
      final db = await DatabaseService.instance.database;
      final List<Map<String, dynamic>> results = await db.query(
        'local_messages',
        columns: ['metadata'],
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (results.isEmpty) return;

      Map<String, dynamic> metadataMap = {};
      if (results.first['metadata'] != null) {
        try {
          metadataMap = Map<String, dynamic>.from(
              jsonDecode(results.first['metadata'] as String));
        } catch (_) {}
      }

      metadataMap['thumbnailUrl'] = thumbnailUrl;

      await db.update(
        'local_messages',
        {
          'metadata': jsonEncode(metadataMap),
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );
      
      if (Get.isRegistered<ChatController>()) {
        Get.find<ChatController>().chatMessages.refresh();
      }
    } catch (e) {
      debugPrint('⚠️ [UploadManager] Failed to update local message thumbnail: $e');
    }
  }

  Future<void> _failLocalMessageUpload(String localId) async {
    try {
      _lastUpdateMs.remove(localId);
      final db = await DatabaseService.instance.database;

      // CRITICAL: Preserve localFilePath and other metadata when marking as failed
      // This ensures the file is not lost and can be retried manually
      final List<Map<String, dynamic>> results = await db.query(
        'local_messages',
        columns: ['metadata'],
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      Map<String, dynamic> metadataMap = {};
      if (results.isNotEmpty && results.first['metadata'] != null) {
        try {
          metadataMap = Map<String, dynamic>.from(
              jsonDecode(results.first['metadata'] as String));
        } catch (e) {
          debugPrint('⚠️ [UploadManager] DB_METADATA_DECODE_FAILED_FAIL: $e');
        }
      }

      // SELF-HEALING: Restore localFilePath if lost from metadata
      if (!metadataMap.containsKey('localFilePath')) {
        final task = _queue.getTaskByMessageId(localId);
        if (task != null) {
          metadataMap['localFilePath'] = task.localFilePath;
          debugPrint(
              '🩹 [UploadManager] DB_METADATA_HEALED_FAIL: Restored localFilePath for $localId');
        }
      }

      debugPrint(
          '💾 [UploadManager] DB_MESSAGE_STATUS_UPDATE: messageId=$localId, status=failed');

      await db.update(
        'local_messages',
        {
          'status': 'failed',
          'metadata': jsonEncode(metadataMap),
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (Get.isRegistered<ChatController>()) {
        Get.find<ChatController>().chatMessages.refresh();
      }
    } catch (e, st) {
      debugPrint(
          '❌ [UploadManager] DB_MESSAGE_STATUS_UPDATE_FAILED: messageId=$localId, error=$e');
      debugPrint('❌ [UploadManager] Stacktrace: $st');
    }
  }

  /// Dispose resources
  void dispose() {
    _retryTimer?.cancel();
    _queue.dispose();
  }
}
