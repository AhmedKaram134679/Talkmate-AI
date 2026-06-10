/// Represents the status of an upload task
enum UploadTaskStatus {
  queued,      // Waiting in queue
  uploading,   // Currently uploading
  completed,   // Successfully uploaded
  paused,      // Paused by user or system
  failed,      // Upload failed
  cancelled    // User cancelled
}

/// Configuration for upload retry behavior
class UploadRetryConfig {
  final int maxAttempts;
  final List<Duration> backoffDurations;
  
  const UploadRetryConfig({
    this.maxAttempts = 3,
    this.backoffDurations = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  });
  
  /// Get backoff duration for attempt number (1-indexed)
  Duration getBackoffDuration(int attemptNumber) {
    if (attemptNumber <= 0) return Duration.zero;
    if (attemptNumber > backoffDurations.length) {
      return backoffDurations.last;
    }
    return backoffDurations[attemptNumber - 1];
  }
}

/// Represents a single upload task
class UploadTask {
  final String taskId;
  final String messageId;
  final String chatId;
  final String userId;
  final String localFilePath;
  final String uploadPath;
  final String mediaType;
  final int fileSizeBytes;
  final DateTime createdAt;
  
  UploadTaskStatus status;
  double progress;
  double? lastPersistedProgress;
  int attemptCount;
  DateTime? lastAttemptAt;
  String? errorMessage;
  String? uploadedUrl;

  final UploadRetryConfig retryConfig;

  UploadTask({
    required this.taskId,
    required this.messageId,
    required this.chatId,
    required this.userId,
    required this.localFilePath,
    required this.uploadPath,
    required this.mediaType,
    required this.fileSizeBytes,
    this.status = UploadTaskStatus.queued,
    this.progress = 0.0,
    this.lastPersistedProgress,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.errorMessage,
    this.uploadedUrl,
    this.retryConfig = const UploadRetryConfig(),
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// Check if upload can be retried
  bool canRetry() {
    return attemptCount < retryConfig.maxAttempts && status == UploadTaskStatus.failed;
  }
  
  /// Get next retry delay
  Duration getNextRetryDelay() {
    return retryConfig.getBackoffDuration(attemptCount);
  }
  
  /// Check if upload is complete
  bool isComplete() {
    return status == UploadTaskStatus.completed && uploadedUrl != null;
  }
  
  @override
  String toString() {
    return 'UploadTask(taskId: $taskId, messageId: $messageId, status: $status, progress: $progress, attempts: $attemptCount)';
  }
}

/// Priority for upload queue
enum UploadPriority {
  low,
  normal,
  high
}

/// Upload task with priority
class PrioritizedUploadTask {
  final UploadTask task;
  final UploadPriority priority;
  
  PrioritizedUploadTask({
    required this.task,
    this.priority = UploadPriority.normal,
  });
  
  int get priorityValue {
    switch (priority) {
      case UploadPriority.low:
        return 1;
      case UploadPriority.normal:
        return 2;
      case UploadPriority.high:
        return 3;
    }
  }
}
