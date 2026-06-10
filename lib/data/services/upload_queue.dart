import 'package:flutter/foundation.dart';
import 'package:talkmate_ai/data/models/upload_task_model.dart';

/// Manages the queue of upload tasks with priority support
class UploadQueue {
  final List<PrioritizedUploadTask> _queue = [];
  
  ValueNotifier<int> get queueLengthNotifier => _queueLengthNotifier;
  final ValueNotifier<int> _queueLengthNotifier = ValueNotifier(0);
  
  /// Get all tasks in queue
  List<UploadTask> getAllTasks() {
    return _queue.map((p) => p.task).toList();
  }
  
  /// Get pending tasks (not completed or failed)
  List<UploadTask> getPendingTasks() {
    return _queue
        .where((p) =>
            p.task.status != UploadTaskStatus.completed &&
            p.task.status != UploadTaskStatus.failed)
        .map((p) => p.task)
        .toList();
  }
  
  /// Add task to queue
  void enqueue(UploadTask task, {UploadPriority priority = UploadPriority.normal}) {
    final prioritized = PrioritizedUploadTask(
      task: task,
      priority: priority,
    );
    _queue.add(prioritized);
    _sortQueue();
    _updateNotifier();
    debugPrint('📤 [UploadQueue] Task enqueued: ${task.taskId} (Priority: $priority)');
  }
  
  /// Get next task to upload
  UploadTask? dequeue() {
    if (_queue.isEmpty) return null;
    
    final prioritized = _queue.removeAt(0);
    _updateNotifier();
    debugPrint('📤 [UploadQueue] Task dequeued: ${prioritized.task.taskId}');
    return prioritized.task;
  }
  
  /// Get task by message ID
  UploadTask? getTaskByMessageId(String messageId) {
    try {
      return _queue
          .firstWhere((p) => p.task.messageId == messageId)
          .task;
    } catch (e) {
      return null;
    }
  }
  
  /// Remove task from queue
  bool removeTask(String taskId) {
    final index = _queue.indexWhere((p) => p.task.taskId == taskId);
    if (index >= 0) {
      _queue.removeAt(index);
      _updateNotifier();
      debugPrint('🗑️ [UploadQueue] Task removed: $taskId');
      return true;
    }
    return false;
  }
  
  /// Move task to front (high priority)
  void prioritizeTask(String taskId) {
    final index = _queue.indexWhere((p) => p.task.taskId == taskId);
    if (index > 0) {
      final task = _queue.removeAt(index);
      // Increase priority
      _queue.insert(0, PrioritizedUploadTask(
        task: task.task,
        priority: UploadPriority.high,
      ));
      _updateNotifier();
      debugPrint('⬆️ [UploadQueue] Task prioritized: $taskId');
    }
  }
  
  /// Clear all tasks
  void clear() {
    _queue.clear();
    _updateNotifier();
    debugPrint('🗑️ [UploadQueue] Queue cleared');
  }
  
  /// Check if queue has pending uploads
  bool hasPendingUploads() {
    return _queue.any((p) => p.task.status == UploadTaskStatus.queued);
  }
  
  /// Get queue size
  int get size => _queue.length;
  
  /// Check if empty
  bool get isEmpty => _queue.isEmpty;
  
  /// Sort queue by priority and creation time
  void _sortQueue() {
    _queue.sort((a, b) {
      // Higher priority first
      if (a.priorityValue != b.priorityValue) {
        return b.priorityValue.compareTo(a.priorityValue);
      }
      // Earlier created tasks first
      return a.task.createdAt.compareTo(b.task.createdAt);
    });
  }
  
  /// Update notifier
  void _updateNotifier() {
    _queueLengthNotifier.value = _queue.length;
  }
  
  /// Dispose resources
  void dispose() {
    _queueLengthNotifier.dispose();
  }
}
