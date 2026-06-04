import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';

import 'audio_presence_controller.dart';
import 'media_hardening_manager.dart';

enum CommSessionStatus {
  idle,
  dialing,
  ringingOutgoing,
  ringingIncoming,
  connecting,
  reconnecting,
  activeAudio,
  activeVideo,
  ended,
  failed
}

/// Network Quality Mapping (Stage R22.1).
enum NetworkQuality { good, fair, poor }

/// Silent Analytics Metadata (Stage R22.4).
class CommSessionTelemetry {
  String? failedReason;
  int videoFallbackCount = 0;
  Duration? ringDuration;
  int reconnectionAttempts = 0;
  int iceFailureCount = 0; // [R33] ICE failure tracking
  int dtlsFailureCount = 0; // [R33] DTLS failure tracking
  DateTime? callStartTime;

  void reset() {
    failedReason = null;
    videoFallbackCount = 0;
    ringDuration = null;
    reconnectionAttempts = 0;
    iceFailureCount = 0;
    dtlsFailureCount = 0;
    callStartTime = null;
  }
}

/// Metadata for a communication session (C10).
class CommSessionMetadata {
  final String sessionId;
  final CommunicationSessionType type;
  final String? callerName;
  final String? participantId;
  final bool isVideo;
  final String? topic;

  CommSessionMetadata({
    required this.sessionId,
    required this.type,
    this.callerName,
    this.participantId,
    this.isVideo = false,
    this.topic,
  });
}

/// Supreme Sovereign Communication Engine (Stage C3).
/// The single source of truth for all communication sessions (Calls & Rooms).
class SovereignCommunicationEngine extends GetxService {
  static SovereignCommunicationEngine get instance =>
      Get.find<SovereignCommunicationEngine>();

  final _activeSessionId = ''.obs;
  final _sessionType = CommunicationSessionType.room.obs;
  final _status = CommSessionStatus.idle.obs;
  final _metadata = Rxn<CommSessionMetadata>();

  final _hardening = Get.find<MediaSessionHardeningManager>();
  final _audioPresence = Get.find<AudioPresenceController>();

  // [Stage R22]: Advanced Stability Layer
  final _networkQuality = NetworkQuality.good.obs;
  final _isFallbackToAudio = false.obs;
  final telemetry = CommSessionTelemetry();

  String get activeSessionId => _activeSessionId.value;
  RxString get activeSessionIdRx => _activeSessionId;
  CommSessionStatus get status => _status.value;
  Rx<CommSessionStatus> get statusRx => _status;
  CommSessionMetadata? get metadata => _metadata.value;
  Rxn<CommSessionMetadata> get metadataRx => _metadata;
  bool get isBusy => _status.value != CommSessionStatus.idle;

  NetworkQuality get networkQuality => _networkQuality.value;
  Rx<NetworkQuality> get networkQualityRx => _networkQuality;
  bool get isFallbackToAudio => _isFallbackToAudio.value;
  RxBool get isFallbackToAudioRx => _isFallbackToAudio;

  /// Requests a lock on communication resources (Mic/Camera).
  /// Ensures only one session (Call or Room) can be active at a time.
  Future<bool> requestSessionLock(
      String sessionId, CommunicationSessionType type,
      {CommSessionMetadata? metadata}) async {
    // [SOVEREIGN_RE-LOCK]: If this is the same session, allow re-locking without resetting status.
    if (_activeSessionId.value == sessionId) {
      if (metadata != null) _metadata.value = metadata;
      return true;
    }

    // [ID_PROMOTION]: If we are already busy with a temporary ID (outgoing_...) and moving to a permanent UUID, promote it.
    if (isBusy &&
        _activeSessionId.value.startsWith('outgoing_') &&
        sessionId.length > 30) {
      debugPrint(
          '🔄 UnifiedComm: PROMOTING session ID from [$_activeSessionId] to [$sessionId]');
      _activeSessionId.value = sessionId;
      if (metadata != null) _metadata.value = metadata;
      return true;
    }

    if (isBusy) {
      debugPrint(
          '🛑 UnifiedComm: Resource conflict! Requested: [$sessionId], Active: [$_activeSessionId]');
      _showGovernanceMessage();
      return false;
    }

    _activeSessionId.value = sessionId;
    _sessionType.value = type;
    _metadata.value = metadata;
    _status.value = CommSessionStatus.connecting;

    // Initialize Telemetry
    telemetry.reset();
    telemetry.callStartTime = DateTime.now();

    debugPrint(
        '🛡️ UnifiedComm: Resource LOCK granted for [${type.name}] session [$sessionId]');
    return true;
  }

  /// Transitions the session to ringing state.
  Future<void> startRinging(
      String sessionId, CommunicationSessionType type, bool isIncoming,
      {CommSessionMetadata? metadata}) async {
    if (_activeSessionId.value != sessionId) return;

    if (metadata != null) _metadata.value = metadata;
    _status.value = isIncoming
        ? CommSessionStatus.ringingIncoming
        : CommSessionStatus.ringingOutgoing;
    debugPrint(
        '🛡️ UnifiedComm: Session [$sessionId] entered RINGING state (${isIncoming ? 'INCOMING' : 'OUTGOING'})');
  }

  /// Activates sovereign protection protocols for the active session.
  Future<void> activateProtection(String userId) async {
    if (!isBusy) return;

    // 1. Audio Presence Registration
    await _audioPresence.requestToSpeak(userId);

    // 2. Security Hardening
    final secured = await _hardening.secureSession('$_activeSessionId:$userId');
    if (secured) {
      final isVideo = _metadata.value?.isVideo ?? false;
      _status.value = isVideo
          ? CommSessionStatus.activeVideo
          : CommSessionStatus.activeAudio;
      debugPrint(
          '✅ UnifiedComm: Protection ACTIVE for session [$_activeSessionId]');
    } else {
      debugPrint(
          '⚠️ UnifiedComm: Security verification weakened for session [$_activeSessionId]');
    }
  }

  /// Releases resources and cleans up session state.
  Future<void> endSession(String userId) async {
    if (!isBusy) return;

    _status.value = CommSessionStatus.ended;

    // 1. Audio Cleanup
    _audioPresence.removeUser(userId);

    // 2. Hardening Release (only if last participant/owner)
    _hardening.releaseSession();

    debugPrint(
        '🧹 UnifiedComm: Session [$_activeSessionId] resources RELEASED.');

    _activeSessionId.value = '';
    _metadata.value = null;
    _isFallbackToAudio.value = false;
    _networkQuality.value = NetworkQuality.good;

    // idle logic: usually we might want a brief 'ended' state before reverting to idle
    // but the engine methods usually drive the transition.
    // For now, let's keep it ending with idle after cleanup.
    _status.value = CommSessionStatus.idle;
  }

  /// Updates network quality and triggers fallback logic if needed (Stage R22.2).
  void updateNetworkQuality(NetworkQuality quality) {
    if (_networkQuality.value == quality) return;
    _networkQuality.value = quality;
    debugPrint(
        '📡 Sovereign Intelligence: Network quality shifted to ${quality.name}');
  }

  /// Sets whether the session is currently in fallback mode (Stage R22.3).
  void setFallback(bool active) {
    if (_isFallbackToAudio.value == active) return;
    _isFallbackToAudio.value = active;
    if (active) telemetry.videoFallbackCount++;
    debugPrint(
        '📡 Sovereign Intelligence: Fallback to Audio Only is now $active');
  }

  /// Transitions to reconnecting state without dropping the call (Stage R22.1).
  void setReconnecting() {
    if (_status.value == CommSessionStatus.reconnecting) return;
    _status.value = CommSessionStatus.reconnecting;
    telemetry.reconnectionAttempts++;
    debugPrint(
        '🔄 Sovereign Intelligence: Session entered RECONNECTING state.');
  }

  /// Unified Error Reporting (C3).
  void reportCommError(String source, dynamic error) {
    debugPrint('🚨 UnifiedComm ERROR [$source]: $error');
    // In future stages, this can trigger AI-driven recovery or telemetry
  }

  /// Sovereign Governance Messaging (C5).
  /// Provides clear feedback to user instead of technical logs.
  void _showGovernanceMessage() {
    if (Get.context == null) {
      debugPrint(
          '⚠️ Governance Message suppressed: Application Context is null.');
      return;
    }
    Get.snackbar(
      'تنبيه سيادي',
      'جهازك مشغول بجلسة اتصال أخرى حالياً. يرجى إنهاء الجلسة الحالية للمتابعة.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Get.theme.colorScheme.errorContainer,
      colorText: Get.theme.colorScheme.onErrorContainer,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(12),
      borderRadius: 16,
      icon: const Icon(Icons.security_rounded),
      mainButton: TextButton(
        onPressed: () {
          if (Get.isSnackbarOpen) Get.back();
          CallManager.instance.terminateCall();
        },
        child: Text(
          Get.locale?.languageCode == 'ar' ? 'إخلاء الجلسة' : 'Force Clear',
          style: TextStyle(
            color: Get.theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
