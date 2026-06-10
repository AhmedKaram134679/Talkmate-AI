import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:talkmate_ai/data/services/media_cache_manager.dart';
import 'package:talkmate_ai/data/services/media_state_store.dart';
import 'package:talkmate_ai/data/services/sqlite_database_service.dart';
import 'package:talkmate_ai/models/message_model.dart';

/// Manages WhatsApp-style sequential voice message playback
class AudioQueueManager {
  static final AudioQueueManager _instance = AudioQueueManager._internal();

  factory AudioQueueManager() {
    return _instance;
  }

  AudioQueueManager._internal();

  final SqliteDatabaseService _db = SqliteDatabaseService();
  final MediaCacheManager _cacheManager = MediaCacheManager();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final RxList<MessageModel> _voiceQueue = <MessageModel>[].obs;
  final RxInt _currentIndex = (-1).obs;
  final RxBool _isPlaying = false.obs;
  final RxDouble _playbackSpeed = 1.0.obs;
  final RxInt _currentPositionMs = 0.obs;
  final RxInt _totalDurationMs = 0.obs;

  bool _isProcessingNext = false;
  String?
      _lastCompletedMessageId; // Dedup: prevents multiple completions for same message
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;

  /// Initialize audio queue manager
  Future<void> initialize() async {
    try {
      _setupPlayerListeners();
      debugPrint('✅ [AudioQueueManager] Initialized');
    } catch (e, st) {
      debugPrint('❌ [AudioQueueManager] Initialization failed: $e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');
      rethrow;
    }
  }

  /// Setup audio player event listeners
  void _setupPlayerListeners() {
    // Cancel existing subscriptions to prevent multiple listeners calling playNext
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      _isPlaying.value = state.playing;

      // WhatsApp behavior: when one audio finishes, the NEXT audio in queue plays automatically
      if (state.processingState == ProcessingState.completed) {
        final completedMsgId = currentMessage?.id;
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_COMPLETED: messageId=$completedMsgId');

        // DEDUP: Prevent multiple completion events for the same message
        if (completedMsgId != null &&
            completedMsgId == _lastCompletedMessageId) {
          debugPrint(
              '🎧 [AudioQueueManager] VOICE_QUEUE_DEDUP: Duplicate completion for $completedMsgId, ignoring');
          return;
        }
        _lastCompletedMessageId = completedMsgId;

        // Synchronous guard: set flag IMMEDIATELY before any async work
        // This prevents race conditions where multiple completions fire
        // before playNext() can set its own guard
        if (_isProcessingNext) {
          debugPrint(
              '🎧 [AudioQueueManager] VOICE_QUEUE_SKIP: playNext already in progress');
          return;
        }
        _isProcessingNext = true;

        // Schedule async progression - flag is already set synchronously
        _progressQueue();
      }
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      _currentPositionMs.value = position.inMilliseconds;
    });

    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _totalDurationMs.value = duration.inMilliseconds;
      }
    });
  }

  /// Internal: progress to next item in queue (called ONLY from listener with lock held)
  Future<void> _progressQueue() async {
    try {
      if (_currentIndex.value < _voiceQueue.length - 1) {
        _currentIndex.value++;
        final nextMsg = _voiceQueue[_currentIndex.value];
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_NEXT: index=${_currentIndex.value}, messageId=${nextMsg.id}');
        await _playMessage(nextMsg);
      } else {
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_END: End of queue reached');
        _isPlaying.value = false;
      }
    } catch (e, st) {
      debugPrint('❌ [AudioQueueManager] VOICE_QUEUE_NEXT_FAILED: $e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');
    } finally {
      // ALWAYS reset flag after completion, even on error
      _isProcessingNext = false;
    }
  }

  /// Build voice queue from consecutive voice messages
  /// Finds all subsequent voice messages starting from selectedMessage
  Future<void> buildQueueFromMessages({
    required List<MessageModel> allMessages,
    required MessageModel selectedMessage,
  }) async {
    try {
      debugPrint(
          '🎧 [AudioQueueManager] VOICE_QUEUE_BUILD_START: selectedId=${selectedMessage.id}, totalMessages=${allMessages.length}');

      // 1. Sort messages strictly by creation time (chronological)
      // This ensures deterministic ordering regardless of input source
      final sortedMessages = List<MessageModel>.from(allMessages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      debugPrint(
          '🎧 [AudioQueueManager] VOICE_QUEUE_ORDER: ${sortedMessages.map((m) => '${m.id} (${m.type})').join(' -> ')}');

      // 2. Find index of selected message in sorted list
      final selectedIndex = sortedMessages.indexWhere(
        (m) => m.id == selectedMessage.id,
      );

      if (selectedIndex < 0) {
        debugPrint(
            '⚠️ [AudioQueueManager] VOICE_QUEUE_BUILD_FAILED: Selected message not found');
        return;
      }

      // 3. Build playback queue from visible voice messages starting from current position
      final queue = <MessageModel>[];

      // Add selected and ALL subsequent voice messages (skipping non-audio)
      // WhatsApp behavior: Text/Images between audio don't stop the queue
      for (int i = selectedIndex; i < sortedMessages.length; i++) {
        if (sortedMessages[i].isAudioMessage) {
          queue.add(sortedMessages[i]);
        } else {
          debugPrint(
              '🎧 [AudioQueueManager] VOICE_QUEUE_SKIP: Skipping non-audio messageId=${sortedMessages[i].id}, type=${sortedMessages[i].type}');
        }
      }

      _voiceQueue.value = queue;
      _currentIndex.value = 0;
      // Reset dedup and processing flag for fresh queue
      _lastCompletedMessageId = null;
      _isProcessingNext = false;

      debugPrint(
          '🎧 [AudioQueueManager] VOICE_QUEUE_BUILD_SUCCESS: queueSize=${queue.length}, messages=${queue.map((m) => m.id).join(' -> ')}');

      if (queue.isNotEmpty) {
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_CURRENT: index=0, messageId=${queue[0].id}');
        await _playMessage(queue[0]);
      }
    } catch (e, st) {
      debugPrint('❌ [AudioQueueManager] VOICE_QUEUE_BUILD_ERROR: $e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');
    }
  }

  /// Play specific message - uses MediaStateStore exclusively for resolution
  Future<void> _playMessage(MessageModel message) async {
    try {
      debugPrint(
          '🎧 [AudioQueueManager] VOICE_PLAY_START: messageId=${message.id}');

      // Resolve media strictly from MediaStateStore
      final resolved =
          MediaStateStore.to.resolveForMessage(message.id, message: message);
      debugPrint(
          '🎧 [AudioQueueManager] MEDIA_AUDIO_RESOLVE: messageId=${message.id}, available=${resolved.isAvailable}, hasLocal=${resolved.hasLocalFile}');

      if (!message.isAudioMessage || !resolved.isAvailable) {
        debugPrint(
            '⚠️ [AudioQueueManager] VOICE_PLAY_INVALID: type=${message.type}, available=${resolved.isAvailable}');
        _isProcessingNext = false; // Reset flag on invalid message
        return;
      }

      String audioFilePath;

      // Priority 1: Local file already exists
      if (resolved.hasLocalFile && resolved.localPath != null) {
        audioFilePath = resolved.localPath!;
      }
      // Priority 2: Cached version of remote URL
      else if (resolved.remoteUrl != null && resolved.remoteUrl!.isNotEmpty) {
        final cachedFile =
            await _cacheManager.getCachedFile(resolved.remoteUrl!) ??
                await _cacheManager.cacheAudio(
                  url: resolved.remoteUrl!,
                  messageId: message.id,
                  chatId: message.chatId,
                );
        if (cachedFile == null) {
          throw Exception('Failed to load audio file from remote');
        }
        audioFilePath = cachedFile.path;
      } else {
        throw Exception('No audio source available');
      }

      // Verify file exists before playback
      if (!File(audioFilePath).existsSync()) {
        throw Exception('Audio file not found at: $audioFilePath');
      }

      // Play audio
      await _audioPlayer.setFilePath(audioFilePath);
      await _audioPlayer.setSpeed(_playbackSpeed.value);
      await _audioPlayer.play();

      // Update database with playback state (using SqliteDatabaseService)
      await _db.updateAudioPlaybackState(
        messageId: message.id,
        currentPositionMs: 0,
        durationMs: _totalDurationMs.value,
        playbackSpeed: _playbackSpeed.value,
        isListened: false,
      );

      debugPrint(
          '🎧 [AudioQueueManager] VOICE_PLAY_SUCCESS: messageId=${message.id}');
      // NOTE: Do NOT reset _isProcessingNext here.
      // The flag is managed by the caller (playNext or _progressQueue)
      // and reset in their finally block. Resetting here creates a race window.
    } catch (e, st) {
      debugPrint(
          '❌ [AudioQueueManager] VOICE_PLAY_FAILED: messageId=${message.id}, error=$e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');

      // Try next message on error (only if queue has more items)
      if (_currentIndex.value < _voiceQueue.length - 1) {
        _currentIndex.value++;
        final nextMsg = _voiceQueue[_currentIndex.value];
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_PLAY_SKIP_TO_NEXT: messageId=${nextMsg.id}');
        await _playMessage(nextMsg);
      } else {
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_PLAY_ERROR_END: No more items in queue');
        _isPlaying.value = false;
      }
    }
  }

  /// Play next message in queue (public API for manual skip)
  Future<void> playNext() async {
    if (_isProcessingNext) {
      debugPrint(
          '🎧 [AudioQueueManager] playNext already in progress, skipping');
      return;
    }

    _isProcessingNext = true;
    // Reset dedup so manual skip works even after auto-completion
    _lastCompletedMessageId = null;

    try {
      if (_voiceQueue.isEmpty) {
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_COMPLETE: Queue was empty');
        _isPlaying.value = false;
        return;
      }

      if (_currentIndex.value < _voiceQueue.length - 1) {
        _currentIndex.value++;
        final nextMsg = _voiceQueue[_currentIndex.value];
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_NEXT: nextIndex=${_currentIndex.value}, nextId=${nextMsg.id}');
        await _playMessage(nextMsg);
      } else {
        debugPrint(
            '🎧 [AudioQueueManager] VOICE_QUEUE_COMPLETE: End of queue reached');
        _isPlaying.value = false;
      }
    } catch (e, st) {
      debugPrint('❌ [AudioQueueManager] VOICE_QUEUE_NEXT_FAILED: $e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');
    } finally {
      _isProcessingNext = false;
    }
  }

  /// Play previous message
  Future<void> playPrevious() async {
    try {
      if (_voiceQueue.isEmpty || _currentIndex.value <= 0) {
        debugPrint('⚠️ [AudioQueueManager] No previous message');
        return;
      }

      _currentIndex.value--;
      await _playMessage(_voiceQueue[_currentIndex.value]);
    } catch (e, st) {
      debugPrint('❌ [AudioQueueManager] Failed to play previous: $e');
      debugPrint('❌ [AudioQueueManager] Stacktrace: $st');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying.value = false;
      debugPrint('⏸️ [AudioQueueManager] Paused');
    } catch (e) {
      debugPrint('❌ [AudioQueueManager] Pause failed: $e');
    }
  }

  /// Resume playback
  Future<void> resume() async {
    try {
      await _audioPlayer.play();
      _isPlaying.value = true;
      debugPrint('▶️ [AudioQueueManager] Resumed');
    } catch (e) {
      debugPrint('❌ [AudioQueueManager] Resume failed: $e');
    }
  }

  /// Set playback speed
  Future<void> setPlaybackSpeed(double speed) async {
    try {
      _playbackSpeed.value = speed;
      await _audioPlayer.setSpeed(speed);
      debugPrint('🎚️ [AudioQueueManager] Speed set to ${speed}x');
    } catch (e) {
      debugPrint('❌ [AudioQueueManager] Speed setting failed: $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
      debugPrint('⏩ [AudioQueueManager] Seeked to ${position.inSeconds}s');
    } catch (e) {
      debugPrint('❌ [AudioQueueManager] Seek failed: $e');
    }
  }

  /// Stop playback and clear queue
  Future<void> stop() async {
    try {
      // Cancel subscriptions first to prevent completion events during stop
      await _playerStateSubscription?.cancel();
      _playerStateSubscription = null;

      await _audioPlayer.stop();
      _voiceQueue.clear();
      _currentIndex.value = -1;
      _isPlaying.value = false;
      _currentPositionMs.value = 0;
      _totalDurationMs.value = 0;
      _isProcessingNext = false;
      _lastCompletedMessageId = null;

      // Re-setup listeners for next playback session
      _setupPlayerListeners();
      debugPrint('🛑 [AudioQueueManager] Stopped');
    } catch (e) {
      debugPrint('❌ [AudioQueueManager] Stop failed: $e');
    }
  }

  // Getters for UI binding
  RxList<MessageModel> get voiceQueue => _voiceQueue;
  RxInt get currentIndex => _currentIndex;
  RxBool get isPlaying => _isPlaying;
  RxDouble get playbackSpeed => _playbackSpeed;
  RxInt get currentPositionMs => _currentPositionMs;
  RxInt get totalDurationMs => _totalDurationMs;

  /// Get current message
  MessageModel? get currentMessage {
    if (_currentIndex.value >= 0 && _currentIndex.value < _voiceQueue.length) {
      return _voiceQueue[_currentIndex.value];
    }
    return null;
  }

  /// Get queue count
  int get queueCount => _voiceQueue.length;

  /// Check if has next message
  bool get hasNext => _currentIndex.value < _voiceQueue.length - 1;

  /// Check if has previous message
  bool get hasPrevious => _currentIndex.value > 0;

  /// Dispose resources
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
  }
}

/// Voice playback controller for UI integration
class VoicePlaybackController extends GetxController {
  final AudioQueueManager _queueManager = AudioQueueManager();

  @override
  Future<void> onInit() async {
    super.onInit();
    await _queueManager.initialize();
  }

  /// Build voice queue from messages
  Future<void> buildQueueFrom({
    required List<MessageModel> messages,
    required MessageModel selectedMessage,
  }) async {
    await _queueManager.buildQueueFromMessages(
      allMessages: messages,
      selectedMessage: selectedMessage,
    );
  }

  // Forward queue manager properties
  RxList<MessageModel> get queue => _queueManager.voiceQueue;
  RxInt get currentIndex => _queueManager.currentIndex;
  RxBool get isPlaying => _queueManager.isPlaying;
  RxDouble get playbackSpeed => _queueManager.playbackSpeed;
  RxInt get positionMs => _queueManager.currentPositionMs;
  RxInt get durationMs => _queueManager.totalDurationMs;

  MessageModel? get currentMessage => _queueManager.currentMessage;
  int get queueCount => _queueManager.queueCount;
  bool get hasNext => _queueManager.hasNext;
  bool get hasPrevious => _queueManager.hasPrevious;

  // Playback controls
  Future<void> playNext() => _queueManager.playNext();
  Future<void> playPrevious() => _queueManager.playPrevious();
  Future<void> pausePlayback() => _queueManager.pause();
  Future<void> resumePlayback() => _queueManager.resume();
  Future<void> setSpeed(double speed) => _queueManager.setPlaybackSpeed(speed);
  Future<void> seekTo(Duration position) => _queueManager.seek(position);
  Future<void> stopPlayback() => _queueManager.stop();

  @override
  void onClose() {
    _queueManager.dispose();
    super.onClose();
  }
}
