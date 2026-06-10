import 'package:talkmate_ai/data/models/upload_task_model.dart';

/// Unified status for media life cycle
enum MediaUploadStatus {
  local, // Exists only locally
  queued, // Enqueued for upload
  uploading, // Currently being uploaded
  uploaded, // Uploaded to storage but not necessarily synced to DB
  synced, // Fully synced to backend database
  failed, // Upload or sync failed
  cancelled // Operation was cancelled
}

/// Central state model for any media message
class MediaState {
  final String messageId;
  final String? localPath;
  final String? remoteUrl;
  final MediaUploadStatus uploadStatus;
  final String? uploadTaskId;
  final double lastKnownProgress;
  final int timestamp;
  final String? errorMessage;
  final String? fileName;
  final String? mediaType;
  final String? thumbnailPath;
  final String? remoteThumbnailUrl;

  MediaState({
    required this.messageId,
    this.localPath,
    this.remoteUrl,
    this.uploadStatus = MediaUploadStatus.local,
    this.uploadTaskId,
    this.lastKnownProgress = 0.0,
    int? timestamp,
    this.errorMessage,
    this.fileName,
    this.mediaType,
    this.thumbnailPath,
    this.remoteThumbnailUrl,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  MediaState copyWith({
    String? messageId,
    String? localPath,
    String? remoteUrl,
    MediaUploadStatus? uploadStatus,
    String? uploadTaskId,
    double? lastKnownProgress,
    int? timestamp,
    String? errorMessage,
    String? fileName,
    String? mediaType,
    String? thumbnailPath,
    String? remoteThumbnailUrl,
  }) {
    return MediaState(
      messageId: messageId ?? this.messageId,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      uploadTaskId: uploadTaskId ?? this.uploadTaskId,
      lastKnownProgress: lastKnownProgress ?? this.lastKnownProgress,
      timestamp: timestamp ?? this.timestamp,
      errorMessage: errorMessage ?? this.errorMessage,
      fileName: fileName ?? this.fileName,
      mediaType: mediaType ?? this.mediaType,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      remoteThumbnailUrl: remoteThumbnailUrl ?? this.remoteThumbnailUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'local_path': localPath,
      'remote_url': remoteUrl,
      'upload_status': uploadStatus.name,
      'upload_task_id': uploadTaskId,
      'last_known_progress': lastKnownProgress,
      'timestamp': timestamp,
      'error_message': errorMessage,
      'file_name': fileName,
      'media_type': mediaType,
      'thumbnail_path': thumbnailPath,
      'remote_thumbnail_url': remoteThumbnailUrl,
    };
  }

  factory MediaState.fromMap(Map<String, dynamic> map) {
    return MediaState(
      messageId: map['message_id'] as String,
      localPath: map['local_path'] as String?,
      remoteUrl: map['remote_url'] as String?,
      uploadStatus: map['upload_status'] != null
          ? MediaUploadStatus.values.byName(map['upload_status'] as String)
          : MediaUploadStatus.local,
      uploadTaskId: map['upload_task_id'] as String?,
      lastKnownProgress:
          (map['last_known_progress'] as num?)?.toDouble() ?? 0.0,
      timestamp:
          map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      errorMessage: map['error_message'] as String?,
      fileName: map['file_name'] as String?,
      mediaType: map['media_type'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      remoteThumbnailUrl: map['remote_thumbnail_url'] as String?,
    );
  }

  /// Helper to convert from UploadTaskStatus
  static MediaUploadStatus fromTaskStatus(UploadTaskStatus status) {
    switch (status) {
      case UploadTaskStatus.queued:
        return MediaUploadStatus.queued;
      case UploadTaskStatus.uploading:
        return MediaUploadStatus.uploading;
      case UploadTaskStatus.completed:
        return MediaUploadStatus.uploaded;
      case UploadTaskStatus.failed:
        return MediaUploadStatus.failed;
      case UploadTaskStatus.cancelled:
        return MediaUploadStatus.cancelled;
      case UploadTaskStatus.paused:
        return MediaUploadStatus.queued; // Or handled as paused if needed
    }
  }
}

/// Resolution object for UI rendering - The ONLY allowed source for media UI
class ResolvedMedia {
  final String messageId;
  final String? localPath;
  final String? remoteUrl;
  final String? fileName;
  final MediaUploadStatus status;
  final double progress;
  final bool isAvailable;
  final String? errorMessage;
  final bool hasLocalFile;
  final String? mediaType;
  final String? thumbnailPath;
  final String? remoteThumbnailUrl;

  ResolvedMedia({
    required this.messageId,
    this.localPath,
    this.remoteUrl,
    this.fileName,
    required this.status,
    required this.progress,
    required this.isAvailable,
    this.errorMessage,
    this.hasLocalFile = false,
    this.mediaType,
    this.thumbnailPath,
    this.remoteThumbnailUrl,
  });

  @override
  String toString() {
    return 'ResolvedMedia(id: $messageId, status: ${status.name}, progress: $progress, available: $isAvailable, hasLocal: $hasLocalFile, mediaType: $mediaType, thumbnailPath: $thumbnailPath, remoteThumbnailUrl: $remoteThumbnailUrl)';
  }
}
