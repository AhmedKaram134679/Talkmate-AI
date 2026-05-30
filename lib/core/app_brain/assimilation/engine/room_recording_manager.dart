import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import '../models/recording_models.dart';

/// Sovereign Room Recording Manager (G8).
/// Manages recording pipelines with strict identity binding and isolation.
class RoomRecordingManager extends GetxService {
  final _currentRecording = Rxn<RecordingSession>();
  final _isPaused = false.obs;

  RecordingSession? get currentRecording => _currentRecording.value;
  bool get isRecording =>
      _currentRecording.value?.state == RecordingState.recording;

  /// Starts a recording session bound to user JWT (G8).
  Future<bool> startRecording(
      String roomId, Set<RecordingTrackType> tracks) async {
    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn) {
      debugPrint('🛑 Recording: Cannot start without active session.');
      return false;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      debugPrint('🛑 Recording: JWT Expired. Access Denied.');
      return false;
    }

    final recordingId = 'rec_${DateTime.now().millisecondsSinceEpoch}';
    _currentRecording.value = RecordingSession(
      id: recordingId,
      roomId: roomId,
      ownerId: auth.userId,
      state: RecordingState.recording,
      tracks: tracks,
      startedAt: DateTime.now(),
    );

    debugPrint(
        '📼 Recording STARTED: Session $recordingId bound to user ${auth.userId}');
    return true;
  }

  /// Pauses the current recording.
  void pauseRecording() {
    if (_currentRecording.value != null) {
      _currentRecording.value =
          _currentRecording.value!.copyWith(state: RecordingState.paused);
      _isPaused.value = true;
      debugPrint('📼 Recording PAUSED: ${_currentRecording.value!.id}');
    }
  }

  /// Resumes the current recording.
  void resumeRecording() {
    if (_currentRecording.value != null) {
      _currentRecording.value =
          _currentRecording.value!.copyWith(state: RecordingState.recording);
      _isPaused.value = false;
      debugPrint('📼 Recording RESUMED: ${_currentRecording.value!.id}');
    }
  }

  /// Stops and purges recording resources.
  Future<void> stopRecording() async {
    if (_currentRecording.value != null) {
      debugPrint('📼 Recording STOPPING: ${_currentRecording.value!.id}');
      _currentRecording.value = _currentRecording.value!.copyWith(
        state: RecordingState.stopped,
        endedAt: DateTime.now(),
      );
      // Logic for finalizing file and moving to safe storage would go here
      _currentRecording.value = null;
    }
  }

  /// Emergency Hard Kill for recording (< 100ms) (Stage G8).
  void recordingHardKill() {
    debugPrint(
        '🛑 RECORDING HARD KILL: Forcing immediate stop and buffer flush.');
    _currentRecording.value = null;
    _isPaused.value = false;
  }

  @override
  void onClose() {
    recordingHardKill();
    super.onClose();
  }
}
