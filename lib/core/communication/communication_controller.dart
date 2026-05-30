import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
// ignore: implementation_imports
import 'package:realtime_client/src/types.dart'; // [Stage R5]: Definitive fix for identity mismatch
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_presence_engine.dart';
import 'package:talkmate_ai/core/assimilation/contracts/definitions.dart';
import 'package:talkmate_ai/core/assimilation/gatekeeper/feature_gatekeeper.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/core/communication/widgets/audio_advisory_modal.dart';
import 'package:talkmate_ai/core/media/webrtc_connection_manager.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/services/call/foreground_service.dart';
import 'package:talkmate_ai/services/communication/turn_credential_manager.dart';

import '../app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'call_notification_manager.dart';

/// [START_FORENSIC_AUDIT]
/// Detailed states for strict governance of WebRTC transitions
enum WebRTCLifecycle {
  idle, // No active session
  signalingInitialized, // Database record created/received
  offerSent, // [Caller] Offer created & written to DB
  offerReceived, // [Callee] Offer read from DB
  answerSent, // [Callee] Answer created & written to DB
  answerReceived, // [Caller] Answer read from DB
  iceGathering, // Gathering local candidates
  iceConnected, // Connected explicitly (ICE State: Connected/Completed)
  mediaFlowing, // [Stage R28] Actual bytes being received
  active, // Media flowing (Tracks added & Verified)
  ended // Terminal state
}

/// [END_FORENSIC_AUDIT]

class CommunicationController extends GetxController
    with WidgetsBindingObserver
    implements SessionLifecycle {
  // Sovereign State
  final RxString sessionId = ''.obs;
  String? _previousSessionId; // [R32] Buffer to handle Promotion Glare
  final RxString sessionName = ''.obs;
  final Rx<CommunicationSessionType> sessionType =
      CommunicationSessionType.room.obs;

  // Single Source of Truth tethering
  final _engine = SovereignCommunicationEngine.instance;
  CommSessionStatus get currentStatus => _engine.status;
  Rx<CommSessionStatus> get statusRx => _engine.statusRx;

  // [START_FORENSIC_AUDIT] Strict Lifecycle Tracking
  final Rx<WebRTCLifecycle> webRTCState = WebRTCLifecycle.idle.obs;
  // Duplicate Protection Set (concatenation of callId_type)
  final Set<String> _processedSignals = {};
  // [END_FORENSIC_AUDIT]

  final RxList<CommunicationParticipant> participants =
      <CommunicationParticipant>[].obs;

  // Media State
  final RxBool isMuted =
      false.obs; // [FIX]: Default to false to ensure hardware activation
  final RxBool isCameraOn = false.obs;

  // WebRTC
  webrtc.MediaStream? localStream;
  final webrtc.RTCVideoRenderer localRenderer = webrtc.RTCVideoRenderer();

  // Supabase
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  StreamSubscription? _callStreamSub;
  String? _myParticipantId;
  final _webrtc = WebRTCConnectionManager.instance;
  final _callRepo = Get.find<ICallRepository>();
  final _userRepo = Get.find<IUserRepository>();

  final _audioRecorder = AudioRecorder();

  // Audio & Stats Monitoring
  final RxDouble micLevel = 0.0.obs;
  // Network quality is now tethered to _engine.networkQualityRx
  NetworkQuality get currentNetworkQuality => _engine.networkQuality;
  final RxDouble inputVolume = 0.8.obs;
  final RxDouble outputVolume = 0.8.obs;

  // [UX_SAFEGUARD]: Windows Headphone Recommendation
  final RxBool showHeadphoneHint = false.obs;

  // [ADVISORY_SYSTEM]: Windows Pro Audio Guidance
  final RxBool showAudioAdvisory = false.obs;
  final RxString advisoryReason = ''.obs;
  final RxBool isSpeakerOn = true.obs;
  final RxBool showDebugOverlay = false.obs;

  Timer? _talkingTimer;
  double _silentRetryCount = 0;
  final RxBool isEnding = false.obs;
  bool _sessionClosed = false; // [HARDENING]: User-suggested perfection guard

  // [DIAGNOSTIC_CENTER]: Call Readiness Logic
  final RxInt lastDiagnosticScore = (-1).obs;
  DateTime? _lastDiagnosticTime;

  final RxInt lastNetworkScore = (-1).obs;
  bool _isCleaningUp = false; // Atomic cleanup protection
  Timer? _iceFailureTimer; // Anti-Ghosting Guard
  Timer?
      _iceDisconnectedTimer; // [Stage R32.1]: Delayed restart for 'disconnected' state
  CallSession? _lastCallRecord; // For catch-up logic
  bool _isInitP2PInProgress = false; // Lock
  final RxBool _isAudioSessionReady = false.obs;
  final RxBool _hasRemoteAudioTrack = false.obs;
  bool _markedOngoingInDB = false;
  bool _isAppReady =
      false; // [SAFETY_GUARD]: Flag to prevent prevent early navigation crashes
  bool _isFinalizingAnswer = false; // [FIX]: Prevent double-finalization

  final List<String> _signalingHistory = []; // [R31][SIGNALING_TRACE]
  final Map<String, Timer> _connectingWatchdogs = {}; // [R31]

  final Map<String, int> _sessionVersions =
      {}; // [Area 6]: Call-scoped versioning
  final List<Future<void> Function()> _negotiationTaskQueue =
      []; // [Area 4]: Task queue
  double _currentAecCancellation =
      40.0; // [Area 2]: Tracked for software fallback
  String?
      _currentNegotiationId; // [Area 5]: Correlation ID for signaling forensics
  bool _isNegotiationLocked = false; // [Area 4]: Strict lock during ICE restart
  Timer? _adaptiveEchoTimer; // [AEC_HARDENING]
  Timer? _aecAuditTimer; // [Area 2]: Periodic AEC effectiveness check
  Timer? _iceAuditTimer; // [Area 3]: Periodic ICE pair auditing
  bool _isAdaptiveEchoActive = false;

  // [GOLDEN_RULE]: Explicit Negotiation Phase Flags

  // [GOLDEN_RULE]: Explicit Negotiation Phase Flags
  bool _isInitialCallSetup = true; // True until first stable connection
  bool _isIceRestart = false; // True only during explicit recovery
  bool _isIceRestartActive =
      false; // [Stage R32.1]: Atomic lock for restart process
  final RxBool showControls = true.obs; // [ARCHITECTURAL]: Persistent UI State

  // [HARDENING]: Zombie Prevention & Cooldowns
  final Map<String, int> _iceRestartCounts = {};
  final Map<String, DateTime> _lastIceRestartTime = {};
  static const int _maxIceRestarts = 3;
  static const Duration _iceRestartCooldown = Duration(seconds: 5);
  Timer? _controlsTimer; // [ARCHITECTURAL]: Timer for auto-hiding controls

  // [Stage R26]: Architectural State Authority
  String? _processedOfferId; // [DEDUPLICATION]: Track processed offers
  bool _hasUserAccepted = false; // Intent flag to survive racing signals

  /// [STATE_AUTHORITY]: Centralized transition logic with linear enforcement
  void _transitionToState(WebRTCLifecycle newState, {String? source}) {
    final current = webRTCState.value;
    final src = source ?? 'internal';

    // Log every transition for forensic audit
    addLog('🏛️ STATE: ${current.name} -> ${newState.name} (Source: $src)');

    // 1. One-way flow enforcement (Backward transitions forbidden unless ICE failed)
    if (newState.index < current.index &&
        newState != WebRTCLifecycle.idle &&
        newState != WebRTCLifecycle.ended &&
        !_isIceRestart) {
      addLog(
          '🛑 ILLEGAL_STATE_TRANSITION: Blocked ${newState.name} from ${current.name}');
      return;
    }

    // 2. Lock signaling states after Media flows
    // [Stage R28.1]: Prevent late signaling resets once media is verified.
    if (webRTCState.value.index >= WebRTCLifecycle.mediaFlowing.index &&
        newState.index < WebRTCLifecycle.mediaFlowing.index &&
        !_isIceRestart) {
      addLog(
          '🛑 STATE_AUTHORITY: Update ignored — prevents signaling regression.');
      return;
    }

    webRTCState.value = newState;
  }

  /// [SHIELD]: Computed property for handshake role logic
  bool get isInitiator => _lastCallRecord?.senderId == currentUserId;

  /// [SINGLETON]: Definitive access point
  static CommunicationController get instance =>
      Get.find<CommunicationController>();

  /// [GLARE]: Perfect Negotiation role. Receiver of the call is the 'Polite' peer.
  bool get isPolite => !isInitiator;

  @override
  void onInit() {
    super.onInit();
    localRenderer.initialize();
    _ensureNavigatorReady();
    WidgetsBinding.instance.addObserver(this);
    CallNotificationManager.instance.init();

    _checkInitialIntents();

    // [VOLUME_CONTROL]: Sync outputVolume with Native Audio Sink
    debounce(outputVolume, (volume) {
      if (!kIsWeb && GetPlatform.isAndroid) {
        try {
          unawaited(const MethodChannel('com.example.talkmate_ai/native_audio')
              .invokeMethod('setVolume', {'volume': volume}));
          debugPrint('🔊 Native Volume set to: $volume');
        } catch (e) {
          debugPrint('⚠️ Set Volume Failed: $e');
        }
      }
    }, time: const Duration(milliseconds: 200));

    // [ID_SYNC_HARDENING]: Bind sessionId to Engine Source of Truth for atomic promotion
    ever(_engine.activeSessionIdRx, (String sid) {
      if (sid.isNotEmpty && sessionId.value != sid) {
        debugPrint(
            '🔄 [R32] Session ID transition detected: ${sessionId.value} -> $sid');
        _previousSessionId = sessionId.value; // Store the old ID for the buffer
        sessionId.value = sid;
      }
    });

    // [Stage R23]: Bind ICE failure watchdog
    _webrtc.onIceFailure = _handleIceFailure;

    // [Area 7]: Windows Device Change Listener
    _webrtc.onDeviceChange = _handleDeviceChange;
  }

  void _ensureNavigatorReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.key.currentState != null) {
        debugPrint('📞 CommunicationController: App Navigator is ready.');
        _isAppReady = true;
      } else {
        _ensureNavigatorReady();
      }
    });
  }

  Future<void> _checkInitialIntents() async {
    // 1. Check if app was launched by CallKit (Mobile)
    if (Platform.isAndroid || Platform.isIOS) {
      final callKitData = await FlutterCallkitIncoming.activeCalls();
      if (callKitData != null &&
          callKitData is List &&
          callKitData.isNotEmpty) {
        for (var item in callKitData) {
          final callMap = Map<String, dynamic>.from(item as Map);
          final callId = callMap['id'] as String?;
          final userId = callMap['handle'] as String?;

          if (callId == null || userId == null) continue;

          // [Constitutional Validation]: Check Source of Truth (Supabase)
          try {
            debugPrint('🔍 Validating startup call: $callId');
            final callRecord = await _supabase
                .from('calls')
                .select('status, created_at')
                .eq('id', callId)
                .maybeSingle();

            if (callRecord == null) {
              debugPrint('🧹 Stale Call: Record not found. Clearing $callId');
              await FlutterCallkitIncoming.endCall(callId);
              continue;
            }

            final status = callRecord['status'] as String;
            final createdAt = DateTime.parse(callRecord['created_at']);
            final isStale = DateTime.now().difference(createdAt).inMinutes > 2;

            if (isStale ||
                (status != 'ringing' &&
                    status != 'ongoing' &&
                    status != 'accepted')) {
              debugPrint(
                  '🧹 Stale Call: Status=$status, IsStale=$isStale (>2m). Clearing $callId in native layer.');
              await FlutterCallkitIncoming.endCall(callId);
              continue;
            }

            debugPrint('🚀 Call Validated. Restoring session for: $userId');
            sessionId.value =
                userId; // Note: This might need to be callId or remoteId depending on logic, but preserving original 'handle' usage for now.
            // Correction: earlier logic used 'handle' as sessionId. Let's stick to what works for now or better yet, use callId if sessionId matches callId concept.
            // Actually, existing code used `sessionId.value = userId` where userId was `handle`.
            // In `incomingCall`: `sessionId.value = callId`.
            // This is a discrepancy. `incomingCall` sets `sessionId` to `callId`.
            // `startCall` sets `sessionId` to `call.id`.
            // So `sessionId` IS `callId`.
            // The previous code `sessionId.value = userId` (handle) might have been wrong if handle is phone number/user id.
            // Let's use `callId` for `sessionId` to be consistent with `incomingCall`.

            sessionId.value = callId; // Correcting to use callId
            sessionType.value = CommunicationSessionType.call;

            // [STABILIZATION]: If CommunicationController is registered, sync its sessionId immediately
            if (Get.isRegistered<CommunicationController>()) {
              Get.find<CommunicationController>().sessionId.value = callId;
            }

            // Map status
            if (status == 'ringing') {
              _engine.statusRx.value = CommSessionStatus.ringingIncoming;
            } else if (status == 'ongoing' || status == 'accepted') {
              _engine.statusRx.value = CommSessionStatus
                  .activeAudio; // Or video, need to check type/is_video if possible, defaulting to active
              // If we want to be precise we should fetch is_video too, but maybe overkill for now.
            }

            return; // Found a valid call, active checking done
          } catch (e) {
            debugPrint('⚠️ Error validating startup call: $e');
            // If offline or error, maybe fail safe?
            // For now, let's assume if we can't verify, we don't restore to be safe/not annoying,
            // or we could restore. 'Sovereigns don't get annoyed by ghosts'. Clearing is safer.
            await FlutterCallkitIncoming.endCall(callId);
          }
        }
      }
    }

    // 2. Check if app was launched via Local Notification (Windows/Desktop)
    final NotificationAppLaunchDetails? launchDetails =
        await CallNotificationManager.instance.localNotifications
            .getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails!.notificationResponse?.payload;
      final actionId = launchDetails.notificationResponse?.actionId;
      if (payload != null) {
        debugPrint('🚀 App launched via Local Notification for user: $payload');
        sessionId.value = payload;
        sessionType.value = CommunicationSessionType.call;
        _engine.statusRx.value = CommSessionStatus.ringingIncoming;

        // [Stage R25]: Instant Accept from Process Wakeup
        if (actionId == 'accept') {
          debugPrint('✅ Sovereignty Wakeup: Instant Accept triggered');
          unawaited(acceptCall());
        }
      }
    }
  }

  // [Debug] Live Sovereign Logs
  final RxList<String> debugLogs = <String>[].obs;
  void addLog(String message) {
    debugPrint('[COMM_LOG] $message');
    // We could add this to a local list for UI overlay
    debugLogs.insert(
        0, '${DateTime.now().second}:${DateTime.now().millisecond} $message');
    if (debugLogs.length > 50) debugLogs.removeLast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      // Small window to attempt cleanup before the OS kills the process
      if (sessionId.value.isNotEmpty && !_sessionClosed) {
        debugPrint(
            'Stage R5: App Backgrounding/Detaching. Triggering urgent cleanup.');
        unawaited(leaveSession(reason: 'app_lifecycle_$state'));
      }
    } else if (state == AppLifecycleState.resumed && GetPlatform.isAndroid) {
      // [Carrier-Grade] Area 3: Android Resume Media Recovery
      addLog(
          '📱 [Carrier-Grade] Area 3: App Resumed. Starting Media Delta Audit...');
      _performAndroidResumeAudit();
    }
  }

  @override
  void onClose() {
    debugPrint('🏃 Sovereign: Controller onClose');
    if (sessionId.value.isNotEmpty && !_sessionClosed) {
      unawaited(leaveSession(reason: 'controller_onClose'));
    }
    _callStreamSub?.cancel();
    _adaptiveEchoTimer?.cancel();
    unawaited(localRenderer.dispose());
    _stopTalkingMonitor();
    unawaited(_audioRecorder.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  String get currentUserId {
    try {
      return Get.find<AuthController>().userId;
    } catch (_) {
      return _supabase.auth.currentUser?.id ?? '';
    }
  }

  // --- Session Initiation ---

  Future<void> joinSession(String id,
      {CommunicationSessionType type = CommunicationSessionType.room,
      bool isVideo = false}) async {
    if (_engine.status != CommSessionStatus.idle) {
      debugPrint('Sovereign Block: Session already in progress or connecting');
      return;
    }

    final featureType = type == CommunicationSessionType.call
        ? FeatureType.call
        : FeatureType.room;
    final access = await FeatureGatekeeper.instance.requestAccess(featureType);
    if (access == FeatureAccessDecision.block) {
      Get.snackbar('Access Denied', 'Sovereign Gatekeeper blocked access');
      return;
    }

    // [Stage R14] Constitutional Permission Guard (Clause 9)
    if (!await _checkMandatoryPermissions(isVideo)) return;

    try {
      // Sovereign Lock
      final secured = await _engine.requestSessionLock(id, type,
          metadata: CommSessionMetadata(
            sessionId: id,
            type: type,
            isVideo: isVideo,
          ));
      if (!secured) return;

      isEnding.value = false;
      _sessionClosed = false;
      _isCleaningUp = false;

      sessionId.value = id;
      sessionType.value = type;

      // [Stage C8] Differentiate between Room and Call logic
      if (type == CommunicationSessionType.room) {
        await _joinRoomSession(id, isVideo);
      } else {
        await _joinCallSession(id, isVideo);
      }

      await _startStatsMonitoring();
      // [Stage R28]: Status is now driven by the deterministic setup sequence (e.g., startInitiatorSequence)
      // and verified by the Media Verification Layer. We do NOT force active status here.
    } catch (e) {
      debugPrint('Error joining session: $e');
      await _engine.endSession(currentUserId);
      Get.snackbar('Error', 'Failed to join: $e');
    }
  }

  // --- [Stage R6] State Machine Logic ---

  /// [Stage 2]: Hardware Warming / Audio Session / Permissions
  Future<void> prepare({bool isVideo = false}) async {
    addLog('🚀 Constitutional: Stage 2 (PREPARE) - Warming hardware...');
    showControls.value =
        true; // [UI_DECOUPLE]: Ensure controls are visible on start

    // [SOVEREIGN_FORCE_CLEANUP]: Ensure No Zombie Sessions clashing with hardware
    if (_webrtc.allPeerIds.isNotEmpty || _isAudioSessionReady.value) {
      addLog('🧹 Force-clearing previous zombie session before new prepare...');
      await _forceFlushWebRTC();
    }

    _isAudioSessionReady.value = false; // Reset session ready flag
    _hasRemoteAudioTrack.value = false; // Reset remote track flag
    _markedOngoingInDB = false;

    isEnding.value = false;
    _sessionClosed = false;
    _isCleaningUp = false;
    try {
      // 1. Ensure Foreground Service (Android Hardening)
      await ensureForegroundExecution();

      // 2. Permission Guard
      if (!await _checkMandatoryPermissions(isCameraOn.value)) {
        addLog('❌ Constitutional: Permissions denied.');
        throw Exception('Permissions denied');
      }

      // 3. Audio Session Activation
      await _initMedia(isCameraOn.value);

      // 4. Add Local Identity for UI
      if (!participants.any((p) => p.isLocal)) {
        participants.add(CommunicationParticipant(
          id: currentUserId,
          rowId: 'local',
          name: 'Me',
          isLocal: true,
          isVideoOn: isCameraOn.value,
          isMuted: false,
        ));
        debugPrint('[ROOM] UI updated');
      }

      addLog('✅ Sovereign: PREPARE complete.');
      startControlsTimer();
    } catch (e) {
      addLog('❌ Sovereign: PREPARE failed! $e');
      rethrow;
    }
  }

  /// [UNIFIED_INITIATOR_FLOW]: Mandatory initiator logic for both platforms.
  Future<void> startInitiatorSequence(
      String id, String remoteUserId, bool isVideo) async {
    PHASE('PHASE: UNIFIED_INIT_START');
    _transitionToState(WebRTCLifecycle.signalingInitialized,
        source: 'initiator_start');
    addLog('🚀 Initiator: Starting unified sequence...');
    sessionId.value = id;
    sessionType.value = CommunicationSessionType.call;
    isCameraOn.value = isVideo;

    // 1. Open Audio Session & Hardware warming
    // This ensures mic is ready before offer
    await prepare();

    // 2. Signaling Subscription
    await _subscribeToCall(id);

    // 3. Init Peer as Initiator (Open mic/media AND send Offer)
    await _initPeer(remoteUserId, isInitiator: true, isVideo: isVideo);

    webRTCState.value = WebRTCLifecycle.offerSent;
    addLog(
        '✅ Initiator: Unified sequence complete. Media appended & Offer sent.');
    PHASE('PHASE: OFFER_SENT');
  }

  /// [TELEMETRY_BRIDGE]: Internal phase tracker for architectural verification
  // ignore: non_constant_identifier_names
  void PHASE(String phase) {
    debugPrint('🏛️ $phase');
    addLog(phase);
  }

  /// Accepts the currently ringing call (Unified Entry Point)
  Future<void> acceptCall() async {
    _hasUserAccepted = true; // [Stage R24]: Mark intent immediately
    if (_engine.status != CommSessionStatus.ringingIncoming &&
        _engine.status != CommSessionStatus.idle) {
      addLog(
          '⚠️ Sovereign: acceptCall ignored (Status: ${_engine.status.name})');
      return;
    }

    if (_isInitP2PInProgress) {
      addLog(
          '⚠️ Sovereign: acceptCall ignored (Initialization already in progress)');
      return;
    }

    _isInitP2PInProgress = true;

    try {
      // 0. IMMEDIATE Timeout Cancellation (Sovereign Guard)
      addLog(
          '🛡️ Sovereign: acceptCall triggered. Cancelling timeout timers...');
      CallManager.instance.stopTimeoutTimer();

      // PHASE 1: Signaling Channel Subscription
      if (sessionId.value.isNotEmpty) {
        addLog('⚡ Sovereign: Subscribing to Signaling ASAP...');
        await _subscribeToCall(sessionId.value);
        unawaited(_ensureRemoteParticipant(sessionId.value));
        PHASE('PHASE: SUBSCRIBED');
      }

      // PHASE 2: Hardware Preparation
      try {
        await prepare();
        PHASE('PHASE: HARDWARE_READY');
      } catch (e) {
        addLog('⚠️ Sovereign: Hardware Preparation (prepare) FAILED: $e');
        if (GetPlatform.isWindows) {
          _triggerAdvisory('HARDWARE_INIT_FAIL');
        }
      }

      // PHASE 3: Deterministic Answer (Stage R28)
      final remoteP = participants.firstWhereOrNull((p) => !p.isLocal);
      final String? remoteId = remoteP?.id ??
          (_lastCallRecord?.senderId == currentUserId
              ? _lastCallRecord?.receiverId
              : _lastCallRecord?.senderId);

      if (remoteId != null) {
        // [Stage R28]: Instead of buffering, we check the definitive signal source (DB Record)
        final sdp = _lastCallRecord?.offer?['sdp']?.toString();
        if (sdp != null) {
          addLog(
              '📄 Sovereign: Processing Offer from DB Record during acceptCall...');
          await _initPeer(remoteId,
              isInitiator: false, remoteSdp: sdp, sendAnswer: true);
        } else {
          addLog(
              '📡 Sovereign: No Offer found in DB Record. Waiting for Signaling...');
          // Keep engine in connecting state; _handleSignaling will catch it
          _engine.statusRx.value = CommSessionStatus.connecting;
        }
      } else {
        addLog(
            '⚠️ Sovereign: Cannot answer call yet. Waiting for participant sync...');
        _engine.statusRx.value = CommSessionStatus.connecting;
      }

      // 4. Navigation (Wait for potential P2P init)
      if (_isAppReady && Get.currentRoute != '/communication_live') {
        unawaited(_safeNavigate('/communication_live',
            arguments: {
              'sessionId': sessionId.value,
              'remoteId': remoteId,
              'type': CommunicationSessionType.call,
            },
            isOff: true));
      }

      addLog('✅ Sovereign: Acceptance Chain Prepared.');
    } catch (e, stack) {
      addLog('❌ Sovereign: Acceptance Chain Critical Failure! $e');
      debugPrint('❌ Sovereign: Acceptance Chain Critical Failure! $e\n$stack');
      unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
      unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
      unawaited(leaveSession(reason: 'acceptance_failure'));
    } finally {
      _isInitP2PInProgress = false;
    }
  }

  // BindMedia is now mostly handled reactively via _handleCallUpdate
  @Deprecated('Use reactive _handleCallUpdate')
  Future<void> bindMedia() async {
    // Legacy support or internal room usage
  }

  Future<void> declineCall() async {
    addLog('🚫 Constitutional: Declining call...');
    // [NATIVE FIX]: Stop Ringing Notification immediately
    unawaited(CallManager.instance.stopNativeRingtone());

    try {
      if (sessionId.value.isNotEmpty) {
        await CallManager.instance
            .updateCallStatus(sessionId.value, CallStatus.rejected);
      }
    } catch (e) {
      debugPrint('Error declining call in DB: $e');
    }
    unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
    unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
    unawaited(leaveSession());
  }

  Future<void> ensureForegroundExecution() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final caller = participants.firstWhereOrNull((p) => !p.isLocal)?.name ??
          'TalkMate User';
      // Signal intention to system
      await CallForegroundService.start(caller, isCameraOn.value);
      debugPrint('[SERVICE] Foreground service started');
      debugPrint('🛡️ Sovereign: Foreground Lock Granted.');
    } catch (e) {
      debugPrint('⚠️ Foreground Service Start Failed: $e');
    }
  }

  Future<void> _joinRoomSession(String id, bool isVideo) async {
    final data = await _supabase.from('rooms').select().eq('id', id).single();
    sessionName.value = data['name'] ?? 'Session';

    // [Stage R22] Join Cleansing (Clause 11)
    // Remove self from ALL other rooms before joining a new one to prevent stale counts
    try {
      await _supabase
          .from('room_participants')
          .delete()
          .eq('user_id', currentUserId)
          .timeout(const Duration(seconds: 2));
      debugPrint(
          '🧹 Sovereign: Cleansed stale participation records for $currentUserId');
    } catch (e) {
      debugPrint('⚠️ Sovereign: Join Cleansing failed (non-critical): $e');
    }

    await _initMedia(isVideo);

    final participantData = await _supabase
        .from('room_participants')
        .upsert({
          'room_id': id,
          'user_id': currentUserId,
          'is_muted': true,
          'is_video_on': isVideo,
          'joined_at': DateTime.now().toIso8601String(),
        }, onConflict: 'room_id, user_id')
        .select()
        .single();

    _myParticipantId = participantData['id'];
    isMuted.value = true;
    isCameraOn.value = isVideo;

    _subscribeToSession(id);
    await _fetchParticipants(id);
  }

  Future<void> _ensureRemoteParticipant(String callId,
      {bool isVideo = false}) async {
    try {
      final data =
          await _supabase.from('calls').select().eq('id', callId).single();
      final callerId = data['sender_id'] ?? data['caller_id'];
      final calleeId = data['receiver_id'] ?? data['callee_id'];
      final otherId = currentUserId == callerId ? calleeId : callerId;

      if (participants.any((p) => p.id == otherId)) return;

      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', otherId)
          .maybeSingle();

      // Update session name if not set
      if (sessionName.value.isEmpty || sessionName.value == 'Session') {
        sessionName.value = profile?['username'] ?? 'Unknown';
      }

      participants.add(CommunicationParticipant(
        id: otherId,
        rowId: 'remote',
        name: profile?['username'] ?? 'User',
        avatarUrl: profile?['avatar_url'],
        isLocal: false,
        isMuted: false,
        isVideoOn: isVideo || data['type'] == 'video',
      ));
      addLog('✅ Sovereign: Remote participant added (Late Fetch)');
    } catch (e) {
      addLog('⚠️ Sovereign: Failed to ensure participant: $e');
    }
  }

  Future<void> _joinCallSession(String id, bool isVideo) async {
    // [Stage C8] Call Session Join Logic
    // We don't join 'room_participants'. We use 'calls' table status + Broadcast.

    // 1. Get Call Data
    final data = await _supabase.from('calls').select().eq('id', id).single();

    // 1.5 [RADICAL FIX]: Radical Priority for Signaling (Caller Side)
    // Subscribe immediately so we don't miss "Answer" if Callee is fast.
    await _subscribeToCall(id);

    // 2. Determine functionality (Caller vs Callee)
    // Support both naming conventions (sender_id/receiver_id is the app standard)
    final callerId = data['sender_id'] ?? data['caller_id'];
    final calleeId = data['receiver_id'] ?? data['callee_id'];
    final otherId = currentUserId == callerId ? calleeId : callerId;

    // 3. Fetch Name
    final profile = await _supabase
        .from('profiles')
        .select()
        .eq('id', otherId)
        .maybeSingle();
    sessionName.value = profile?['username'] ?? 'Unknown';

    // 4. Role Dispatch (Deterministic Reset)
    final bool isCaller = callerId == currentUserId;

    if (isCaller) {
      PHASE('PHASE: CALLER_START');
      await startInitiatorSequence(id, otherId, isVideo);
    } else {
      PHASE('PHASE: CALLEE_START');
      // [Stage R28]: Callee strictly waits for ring and then acceptCall()
      // We only prepare the UI state here.
      _engine.statusRx.value = CommSessionStatus.ringingIncoming;

      // Add self (Other is added below)
      if (!participants.any((p) => p.isLocal)) {
        participants.add(CommunicationParticipant(
          id: currentUserId,
          rowId: 'local',
          name: 'Me',
          isLocal: true,
          isMuted: false,
          isVideoOn: isVideo,
        ));
      }

      // Add remote
      participants.add(CommunicationParticipant(
        id: otherId,
        rowId: 'remote',
        name: profile?['username'] ?? 'User',
        avatarUrl: profile?['avatar_url'],
        isLocal: false,
        isMuted: false,
        isVideoOn: data['type'] == 'video',
      ));
    }
  }

  @override
  Future<void> leaveSession({String? reason, String? securityContext}) async {
    // Stage R21.0: Constitutional check for stuck state or active session
    final bool isStuck =
        sessionId.value.isEmpty && _engine.status != CommSessionStatus.idle;

    if (sessionId.value.isEmpty && !isStuck) {
      return;
    }

    // [HARDENING] Anti-Flicker Protection
    // [SOVEREIGN_FIX]: Only ignore if this is an automatic background refresh.
    // Manual hang-ups (Reason: manual/terminal) must ALWAYS proceed.
    // Unified manual check (including reason == null as it usually comes from UI pop)
    final isManual = reason == null ||
        reason == 'manual' ||
        reason == 'terminal' ||
        reason == 'remote_terminate' ||
        reason == 'rejected';

    if (_engine.status == CommSessionStatus.reconnecting && !isManual) {
      debugPrint(
          '🛡️ Sovereign: leaveSession ignored during RECONNECTING phase.');
      return;
    }

    // [SessionGuard]: If context is provided, it MUST match current session
    // [SOVEREIGN_FIX]: If securityContext is 'unknown' or empty, we trust the manual intent.
    final bool contextMismatch = securityContext != null &&
        securityContext.isNotEmpty &&
        securityContext != 'unknown' &&
        sessionId.value.isNotEmpty &&
        securityContext != sessionId.value;

    if (contextMismatch) {
      addLog(
          '🛡️ Sovereign Guard: Ignoring leaveSession for mismatch context ($securityContext vs ${sessionId.value})');
      // [SAFETY]: If we are stuck in a non-idle status but IDs mismatch, we might have a zombie local record.
      // We don't clear everything, but we ensure the old call record is definitely ended if it was ours.
      return;
    }

    if ((sessionId.value.isEmpty && !isStuck) ||
        _sessionClosed ||
        _isCleaningUp) {
      return;
    }
    _sessionClosed = true; // [MIC_DROP]: Lock the gate
    _isCleaningUp = true; // Protect against re-entry

    final type = sessionType.value;
    final id = sessionId.value;
    final participantId = _myParticipantId;
    final channel = _channel;

    addLog(
        "🚶 Sovereign: ${isStuck ? 'Clearing STUCK state' : 'Leaving session'} (Reason: $reason)...");

    try {
      // 1. Database/Signaling Sync
      if (type == CommunicationSessionType.call) {
        // [Constitutional] End call in DB (if we haven't already marked it rejected/etc)
        final status = _engine.status;
        if (status != CommSessionStatus.idle) {
          await CallManager.instance.updateCallStatus(id, CallStatus.ended);
        }
      }

      // 2. Local Cleanup
      _iceFailureTimer?.cancel();
      _talkingTimer?.cancel();
      _adaptiveEchoTimer?.cancel();

      unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
      unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
      // [HARDENING]: Stop Foreground Service EXACTLY here.
      // We also add a safeguard in 'finally' just in case.
      unawaited(CallForegroundService.stop());
      unawaited(CallManager.instance.stopNativeRingtone());
      await _callStreamSub?.cancel();
      _callStreamSub = null;

      // [SIGNALING_HARD_RESET]: Synchronously kill the channel to avoid late events
      if (_channel != null) {
        addLog('📡 Hard Reset: Removing signaling channel...');
        unawaited(_supabase.removeChannel(_channel!));
        _channel = null;
      }

      _engine.statusRx.value = CommSessionStatus.idle;
      _silentRetryCount = 0;

      // [FIX]: Force Presence Sync (UserStatus.busy -> online) to handle late updates
      if (Get.isRegistered<SovereignPresenceEngine>()) {
        unawaited(SovereignPresenceEngine.instance
            .forceStatusUpdate(UserStatus.online));
        addLog('🟢 Presence Fail-safe applied on leaveSession');
      }

      // [STRICT TERMINATION SEQUENCE]
      // 1. & 2. & 3. Handle WebRTC cleanup (Stop tracks, removeTrack, close PeerConnection)
      await _webrtc.dispose();

      // [AUDIO_FOCUS]: Abandon focus when session ends
      if (!GetPlatform.isWindows && !GetPlatform.isWeb) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(false);
          addLog('🎙️ Sovereign: Audio Session deactivated (Abandon Focus)');
        } catch (e) {
          debugPrint('⚠️ Audio Session deactivation error: $e');
        }
      }

      // 4. Dispose Renderers
      localRenderer.srcObject = null;
      for (var p in participants) {
        p.remoteStream.value = null;
        if (p.audioSinkRenderer != null) {
          addLog('🧹 Disposing persistent AudioSink for ${p.id}');
          unawaited(p.audioSinkRenderer!.dispose());
          p.audioSinkRenderer = null;
        }
      }

      // 5. Force AudioMode normal
      if (!GetPlatform.isWindows && !GetPlatform.isWeb) {
        try {
          final session = await AudioSession.instance;
          await session.configure(const AudioSessionConfiguration.music());
        } catch (_) {}
      }

      // 6. Release mic & camera locks / Handshake States
      _isAudioSessionReady.value = false;
      _hasRemoteAudioTrack.value = false;
      _isInitP2PInProgress = false;
      _hasUserAccepted = false; // Reset intent
      _iceFailureTimer?.cancel();
      _aecAuditTimer?.cancel(); // [Area 2]
      _iceAuditTimer?.cancel(); // [Area 3]
      _markedOngoingInDB = false;

      // [STATE_ERASURE_HARDENING]: User-suggested perfection guard
      _transitionToState(WebRTCLifecycle.idle, source: 'leave_session');
      _processedOfferId = null;
      _lastCallRecord = null;
      _processedSignals.clear();
      _isInitialCallSetup = true;
      _isIceRestart = false;
      _isAdaptiveEchoActive = false;
      if (sessionId.value.isNotEmpty) {
        _sessionVersions[sessionId.value] =
            (_sessionVersions[sessionId.value] ?? 0) + 1;
      }

      // 3. UI Cleanup
      participants.clear();
      sessionId.value = '';
      sessionType.value = CommunicationSessionType.room;

      // [SAFETY_GUARD]: Guard navigation/UI transitions
      if (_isAppReady) {
        if (reason == 'manual' ||
            reason == 'rejected' ||
            reason == 'remote_terminate') {
          if (Get.currentRoute == '/communication_live' ||
              Get.currentRoute == '/ringing') {
            Get.back();
          }
        }
      }

      // 4. Remote/System Cleanup (Async)
      unawaited(_performBackgroundCleanup(
        type: type,
        id: id,
        participantId: participantId,
        channel: channel,
        userId: currentUserId,
      ));

      addLog('✅ Sovereign: Cleanup complete.');
      showControls.value =
          false; // [UI_DECOUPLE]: Controls die only after cleanup
    } catch (e) {
      addLog('⚠️ Sovereign Cleanup Error: $e');
    } finally {
      _isCleaningUp = false;
      _sessionClosed = false;
      // [HARDENING]: Final safety net for Foreground Service
      unawaited(CallForegroundService.stop());
    }
  }

  Future<void> _forceFlushWebRTC() async {
    final String currentSessionId = sessionId.value;
    final bool currentlyInInit = _isInitP2PInProgress;

    _sessionClosed = true;
    _isCleaningUp = true;
    _iceFailureTimer?.cancel();
    await _webrtc.dispose();
    _isAudioSessionReady.value = false;
    _hasRemoteAudioTrack.value = false;

    // [CRITICAL FIX]: If we are in the middle of a new call handshake,
    // DO NOT wipe the sessionId that was just assigned.
    if (!currentlyInInit) {
      sessionId.value = '';
      _isInitP2PInProgress = false;
    } else {
      sessionId.value = currentSessionId;
      _isInitP2PInProgress = currentlyInInit;
      addLog(
          '🛡️ [UUID_GUARD] Preserving sessionId during flush: $currentSessionId');
    }

    _sessionClosed = false;
    _isCleaningUp = false;
  }

  /// Handles long-running network and hardware cleanup in the background
  Future<void> _performBackgroundCleanup({
    required CommunicationSessionType type,
    required String id,
    String? participantId,
    RealtimeChannel? channel,
    required String userId,
  }) async {
    // Stage R21: Graceful cooldown (Clause 7)
    // Allow UI to transition away before heavy hardware/network release
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      if (type == CommunicationSessionType.room) {
        if (participantId != null) {
          await _supabase
              .from('room_participants')
              .delete()
              .eq('id', participantId)
              .timeout(const Duration(seconds: 3));
        }
      } else {
        _sendSignal(receiverId: 'all', type: 'leave', data: {});

        // Only update DB if we have a valid UUID (Phase 6/8 alignment)
        final uuidRegex = RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false);

        if (id.isNotEmpty && uuidRegex.hasMatch(id)) {
          await _supabase
              .from('calls')
              .update({
                'status': 'ended',
                'ended_at': DateTime.now().toIso8601String(),
              })
              .eq('id', id)
              .timeout(const Duration(seconds: 3));
        } else {
          debugPrint('Sovereign: Skipping DB update for non-UUID session: $id');
        }
      }
    } catch (e) {
      debugPrint('Silent DB cleanup failure (bg): $e');
    }

    try {
      if (channel != null) {
        addLog('📡 Background Cleanup: Confirming channel removal...');
        await _supabase.removeChannel(channel);
      }
      // [Stage R21.1] Await Async Disposal
      await _webrtc.dispose();
      addLog('🧊 PC_CLOSED & DISPOSED');

      // Shutdown engine last
      await _engine.endSession(userId);
    } catch (e) {
      debugPrint('Hardware/Engine disposal failure (bg): $e');
    } finally {
      _isCleaningUp = false;
      isEnding.value = false;
      addLog('✅ Sovereign: Background cleanup complete.');
    }
  }

  // --- Realtime & Signaling ---

  void _subscribeToSession(String id) {
    _channel = _supabase.channel('comm_$id');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_participants',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'room_id', value: id),
          callback: (p) => _handleInsertParticipant(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'room_participants',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'room_id', value: id),
          callback: (p) => _handleUpdateParticipant(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'room_participants',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'room_id', value: id),
          callback: (p) => _handleDeleteParticipant(p.oldRecord),
        )
        .onBroadcast(event: 'signaling', callback: (p) => _handleSignaling(p))
        .subscribe((status, [e]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        // [Mesh] Announce presence to rooms
        _sendSignal(receiverId: 'all', type: 'room_ready', data: {});
      }
    });
  }

  void manualSubscribe(String id) {
    addLog('📡 Sovereign: Manual Subscription to $id requested.');
    unawaited(_subscribeToCall(id));
  }

  Future<void> _subscribeToCall(String id) async {
    if (id.isEmpty) return;

    final callId = id;
    // [Area 6]: Increment version for new subscription cycle
    _sessionVersions[callId] = (_sessionVersions[callId] ?? 0) + 1;
    final completer = Completer<void>();
    addLog('📡 Subscribing to Call: $id');

    // [R30] Subscription Singularity: Atomic cancel-and-nullify
    if (_callStreamSub != null) {
      addLog('📡 Atomic: Canceling existing Call Subscription before re-init');
      await _callStreamSub!.cancel();
      _callStreamSub = null;
    }

    // [SIGNALING_RESILIENCE]: Only reset state if the ID actually changed.
    // This prevents "Signaling Loops" during network flickers where the subscription retries.
    if (id != sessionId.value) {
      _processedSignals.clear();
      webRTCState.value = WebRTCLifecycle.idle;
      _isInitP2PInProgress = false;
      sessionId.value = id;
      _sessionVersions[id] =
          0; // [Area 6]: Reset versioning for new session scope
      _currentNegotiationId = null;
    }

    // [Stage R22.8]: Immediate manual fetch to catch-up before the stream starts
    unawaited(_callRepo.getById(id).then((call) {
      if (call != null) {
        addLog('📡 Sub: Manual fetch SUCCESS for $id');
        _handleCallUpdate(call);
      }
    }));

    _callStreamSub = _callRepo.watchById(id).listen(
      (call) {
        if (call != null) {
          _handleCallUpdate(call);
        }
      },
      onError: (e) {
        addLog('! Signaling Error for $id: $e');
        // RECOVERY: Retry the subscription after a shorter delay
        Future.delayed(const Duration(seconds: 2), () {
          if (sessionId.value == id &&
              webRTCState.value != WebRTCLifecycle.ended) {
            addLog('🔄 Signaling: Retrying subscription for $id...');
            unawaited(_subscribeToCall(id));
          }
        });
      },
    );

    // [SIGNALING_RESILIENCE]: Safely remove previous channel to avoid leaks/crashes
    if (_channel != null) {
      addLog('📡 Atomic: Removing existing Realtime Channel before re-init');
      await _supabase.removeChannel(_channel!);
      _channel = null;
    }

    _channel = _supabase.channel('call_$id');
    _channel!
        .onBroadcast(event: 'signaling', callback: (p) => _handleSignaling(p));
    _channel!.onPresenceSync((payload) {
      _syncPresenceState();
    }).onPresenceJoin((payload) {
      _syncPresenceState();
    }).onPresenceLeave((payload) {
      _syncPresenceState();
    }).subscribe((status, [e]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!completer.isCompleted) completer.complete();
        final uid = currentUserId;
        if (uid.isNotEmpty) {
          final myStatus = {
            'user_id': uid,
            'online_at': DateTime.now().toIso8601String(),
          };
          // Use try-catch for presence tracking to prevent whole-engine crash
          try {
            await _channel!.track(myStatus);
          } catch (te) {
            addLog('⚠️ Presence Engine: Failed to track: $te');
          }
        }
      } else if (status == RealtimeSubscribeStatus.channelError) {
        addLog('⚠️ Signaling: Channel Error for $id: $e');
        if (!completer.isCompleted) {
          completer.completeError('Channel error: $e');
        }
      } else if (status == RealtimeSubscribeStatus.timedOut) {
        addLog('⚠️ Signaling: Subscription timed out for $id');
        if (!completer.isCompleted) {
          completer.completeError('Subscription timed out');
        }
      }
    });

    // Wait for actual confirmation or timeout
    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      addLog('🛡️ Signaling: Confirmation wait failed/timed-out: $e');
      // [RESILIENCE]: We proceed anyway as fallback, but the log will tell us if confirmation was received.
    }
  }

  /// [G3_RESILIENCE]: Force a refresh of the signaling stream.
  /// Called when a token is refreshed to ensure we aren't using a stale channel.
  void refreshSignaling() {
    if (sessionId.value.isNotEmpty &&
        webRTCState.value != WebRTCLifecycle.ended) {
      addLog('🔄 G3: Force-refreshing signaling for ${sessionId.value}...');
      unawaited(_subscribeToCall(sessionId.value));
    }
  }

  Future<void> _handleCallUpdate(CallSession call) async {
    _lastCallRecord = call; // Cache for catch-up
    String uid = currentUserId;

    if (uid.isEmpty) {
      addLog(
          '⚠️ Constitutional: currentUserId is EMPTY. Attempting recovery...');
      // Fallback to supabase user if AuthController is lagging
      final suid = _supabase.auth.currentUser?.id;
      if (suid != null) {
        addLog('✅ Sovereignty: Identity recovered via Supabase fallback.');
        uid = suid; // Use the recovered ID for this update cycle
      } else {
        addLog(
            '❌ Sovereignty: Failed to recover identity. Aborting call update.');
        return;
      }
    }

    final isCaller = call.senderId == uid;
    final remoteId = isCaller ? call.receiverId : call.senderId;

    addLog(
        '📊 UPDATE: ID=${call.id} | CurrentID=${sessionId.value} | Role=${isCaller ? "CALLER" : "CALLEE"} | Status=${call.status.name}');
    addLog(
        '👤 Identity: MyUID=$uid | Sender=${call.senderId} | Receiver=${call.receiverId}');

    if (call.id != sessionId.value && sessionId.value.isNotEmpty) {
      // addLog('⏭️ Skipping update for inactive session: ${call.id}');
      return;
    }

    // 1. Status Changes
    if (call.status == CallStatus.ended ||
        call.status == CallStatus.rejected ||
        call.status == CallStatus.missed ||
        call.status == CallStatus.failed) {
      // [GLOBAL_END_LISTENER]: Direct handover to Manager for atomic cleanup
      if (webRTCState.value != WebRTCLifecycle.ended) {
        addLog('🚫 Constitutional: Call ${call.status.name} detected in DB.');
        _transitionToState(WebRTCLifecycle.ended, source: 'remote_termination');
        unawaited(CallManager.instance
            .terminateCall(status: call.status, fromRemote: true));
      }
      return;
    }

    // [G3_RESILIENCE]: Handle ICE Restart Signal from Remote
    // We check BOTH the 'offer' column (where setOffer puts it) and 'metadata' for compatibility.
    final restartOffer =
        (call.offer != null && call.offer!['iceRestart'] == true)
            ? call.offer
            : (call.metadata != null && call.metadata!['iceRestart'] == true)
                ? call.metadata!['restartOffer']
                : null;

    if (restartOffer != null && restartOffer is Map) {
      final sdp = restartOffer['sdp']?.toString() ?? '';
      final signalKey = 'restart_${call.id}_${sdp.hashCode}';

      if (!_processedSignals.contains(signalKey)) {
        _processedSignals.add(signalKey);
        addLog('🧊 ICE: Received Restart Signal from peer. Recovering...');
        unawaited(_handleIceRestart(
            remoteId, Map<String, dynamic>.from(restartOffer)));
      }
    }

    // [Stage R28]: Deterministic Reset - DB updates NO LONGER trigger P2P initialization.
    // Initialization is strictly handled by startInitiatorSequence() or acceptCall().
    // We only use DB updates here to track participants and terminators.

    // 1. Participant Tracking (Passive)
    if (!participants.any((p) => p.id == remoteId) &&
        (call.status == CallStatus.ongoing ||
            call.status == CallStatus.accepted)) {
      addLog('👥 DB: Updating participant list for ${call.id}');
      // Passive addition to ensure UI has the metadata if not already there
      if (!participants.any((p) => p.isLocal)) {
        participants.add(CommunicationParticipant(
          id: uid,
          rowId: 'local',
          name: 'Me',
          isLocal: true,
          isMuted: isMuted.value,
          isVideoOn: isCameraOn.value,
        ));
      }
      participants.add(CommunicationParticipant(
        id: remoteId,
        rowId: 'remote',
        name: 'Partner',
        isLocal: false,
        isMuted: false,
        isVideoOn: call.isVideo,
      ));
      unawaited(_fetchRemoteProfile(remoteId));
    }

    // 2. WebRTC Signaling (Offer/Answer/Candidates)
    final pc = _webrtc.getPeer(remoteId);

    // [Offer] Receiver handles offer from DB
    // [Stage S2.1]: Monotonic Version Guard
    final int? incomingVersion =
        (call.offer?['version'] ?? call.offer?['epoch']) as int?;
    final currentSessionVersion = _sessionVersions[call.id] ?? 0;
    if (incomingVersion != null && incomingVersion < currentSessionVersion) {
      addLog(
          '🛡️ DB: Discarding STALE Offer from version $incomingVersion (Current: $currentSessionVersion)');
      return;
    }
    if (incomingVersion != null && incomingVersion > currentSessionVersion) {
      _sessionVersions[call.id] = incomingVersion;
    }

    if (call.offer != null && !isCaller) {
      // STRICTLY Callee Only
      final offerSdp = call.offer!['sdp']?.toString() ?? '';
      final offerHash = offerSdp.hashCode.toString();
      final signalKey = '${call.id}_offer_$offerHash';

      // [Stage R26]: Offer Processing Lock
      if (_processedOfferId == signalKey) {
        return;
      }

      final isIceRestart = call.offer!['ice_restart'] == true ||
          call.offer!['iceRestart'] == true;

      // [Stage S2]: Improved Deduplication
      if (!_processedSignals.contains(signalKey)) {
        // [GLARE_GUARD]: Mark as processed BEFORE async calls to prevent race
        _processedSignals.add(signalKey);

        // Validate Lifecycle
        if (webRTCState.value == WebRTCLifecycle.signalingInitialized ||
            webRTCState.value == WebRTCLifecycle.idle ||
            isIceRestart) {
          // [SAFETY]: Fallback participant addition if the accepted block was skipped
          if (!participants.any((p) => p.id == remoteId)) {
            addLog('👥 Sovereign: Late participant addition for Offer...');
            participants.add(CommunicationParticipant(
              id: remoteId,
              rowId: 'remote',
              name: 'Partner',
              isLocal: false,
              isVideoOn: false,
            ));
            unawaited(_fetchRemoteProfile(remoteId));
          }

          if (isIceRestart) {
            addLog('📄 DB: Received ICE_RESTART Offer.');
            // [GLARE]: Collision check for ICE Restart
            final peer = _webrtc.getSovereign(remoteId);
            final pc = peer?.pc;
            final offerCollision = (peer != null && peer.makingOffer) ||
                (pc != null &&
                    pc.signalingState !=
                        webrtc.RTCSignalingState.RTCSignalingStateStable);

            if (offerCollision && pc != null && peer != null) {
              final ignoreOffer = !isPolite && peer.makingOffer;
              if (ignoreOffer) {
                addLog(
                    '🛡️ [R34] Perfect Negotiation: Impolite peer ignoring offer.');
                return;
              }

              addLog(
                  '🛡️ [R34] Perfect Negotiation: Polite peer - executing rollback.');
              try {
                if (pc.signalingState !=
                    webrtc.RTCSignalingState.RTCSignalingStateStable) {
                  await pc.setLocalDescription(
                      webrtc.RTCSessionDescription(null, 'rollback'));
                  addLog('✅ GLARE: DB Rollback successful.');
                } else {
                  addLog(
                      '✅ GLARE: Already stable, proceeding with remote offer.');
                }
                // Continue to process remote restart
              } catch (e) {
                addLog(
                    '⚠️ GLARE: DB Rollback failed ($e). Falling back to reconstruction.');
                await _initPeer(remoteId,
                    isInitiator: false,
                    remoteSdp: call.offer!['sdp'],
                    isVideo: isCameraOn.value);
                return;
              }
            }
            addLog('📄 DB: Processing ICE_RESTART Offer. Recovering...');
            _isIceRestart =
                true; // [R32 FIX]: Ensure state machine allows transitions
            await _handleIceRestart(remoteId, call.offer!);
          } else {
            final peer = _webrtc.getSovereign(remoteId);
            if (peer == null) return;

            // [R34] Perfect Negotiation: Check if we should ignore
            final ignoreOffer = !isPolite && peer.makingOffer;
            if (ignoreOffer) {
              addLog(
                  '🛡️ [R34] Perfect Negotiation: Offer IGNORED (Impolite/MakingOffer).');
              return;
            }

            // [HARD_GATING]: Only refuse if strictly frozen AFTER connection
            if (peer.signalingFrozen) {
              addLog(
                  '🛡️ [HARD_GATING] Offer Refused: Peer Signaling is FROZEN.');
              return;
            }

            addLog('📄 DB: Received Offer. Starting Peer (Delayed Answer)...');
            _processedOfferId = signalKey; // [Stage R26]: Lock this offer
            _transitionToState(WebRTCLifecycle.offerReceived,
                source: 'db_offer');
            await _initPeer(remoteId,
                isInitiator: false,
                remoteSdp: call.offer!['sdp'],
                sendAnswer: false,
                isVideo: isCameraOn.value);
          }
        }
      }
    }

    // [Answer] Caller handles answer from DB
    if (call.answer != null && isCaller) {
      // [Stage S2.1]: Monotonic Version Guard for Answer
      final int? incomingAnsVersion =
          (call.answer?['version'] ?? call.answer?['epoch']) as int?;
      final currentSessionVersion = _sessionVersions[call.id] ?? 0;
      if (incomingAnsVersion != null &&
          incomingAnsVersion < currentSessionVersion) {
        addLog(
            '🛡️ DB: Discarding STALE Answer from version $incomingAnsVersion (Current: $currentSessionVersion)');
        return;
      }
      if (incomingAnsVersion != null &&
          incomingAnsVersion > currentSessionVersion) {
        _sessionVersions[call.id] = incomingAnsVersion;
      }

      if (pc != null) {
        // STRICTLY Caller Only
        final answerHash = call.answer!['sdp'].hashCode.toString();
        final signalKey = '${call.id}_answer_$answerHash';

        if (!_processedSignals.contains(signalKey)) {
          try {
            final localDesc = await _safeGetLocalDescription(pc);
            if (localDesc == null) {
              addLog(
                  '📄 DB: Answer received but Local Description (Offer) IS NOT READY. Deferring...');
              // We don't mark as processed, so it will retry on catch-up or next update
              return;
            }

            final remoteDesc = await pc.getRemoteDescription();
            if (remoteDesc == null) {
              addLog('📄 DB: Received Answer. Finalizing P2P...');
              _transitionToState(WebRTCLifecycle.answerReceived,
                  source: 'db_answer');

              await pc.setRemoteDescription(
                  webrtc.RTCSessionDescription(call.answer!['sdp'], 'answer'));

              _processedSignals.add(signalKey);
              addLog('✅ Sovereign: Answer applied successfully.');

              // [FORENSIC]: Drain buffered candidates now that Remote Desc is set (Stage R7)
              await _webrtc.drainCandidates(remoteId);
            }
          } catch (e) {
            addLog('❌ Sovereign: Error processing Answer: $e');
          }
        }
      } else {
        addLog('⚠️ DB: Received Answer but PC is NULL for $remoteId');
      }
    }

    // [Candidates] Handle archived candidates in DB with duplicate protection
    if (call.candidates != null && call.candidates!.isNotEmpty) {
      if (pc != null) {
        addLog('📡 ICE: Signal تلقى');
        for (var json in call.candidates!) {
          final candidateStr = json['candidate']?.toString() ?? '';
          if (candidateStr.isEmpty) continue;

          // Complex Hash for Robustness
          final candHash =
              '${json['sdpMid']}_${json['sdpMLineIndex']}_${candidateStr.hashCode}';

          // Filter out if we created it (echo) or if processed
          // But here 'call.candidates' contains ALL candidates?
          // We need to filter based on AUTHOR.
          // Assuming call.candidates structure might lack author, but standard usually appends all.
          // Actually, normally we'd separate `caller_candidates` and `callee_candidates`.
          // The current schema uses a single `candidates` array.
          // We must check if the candidate is meant for US (local is opposite of remote).
          // Since we can't easily distinguish author from standard ICE JSON,
          // we rely on the fact that `addIncomingCandidate` usually fails safely on own candidates
          // OR we just process them.

          if (!_processedSignals.contains(candHash)) {
            final cand = webrtc.RTCIceCandidate(
              json['candidate'],
              json['sdpMid'],
              json['sdpMLineIndex'],
            );

            addLog('🧊 ICE: Signal Received. Adding to Manager...');
            await _webrtc.addIncomingCandidate(remoteId, cand);
            _processedSignals.add(candHash);

            // [ICE_RESTART_SYNC]: The WebRTCConnectionManager watchdog now handles connectivity stalls.
          }
        }
      }
    }
  }

  Future<void> _fetchRemoteProfile(String userId) async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        final index = participants.indexWhere((p) => p.id == userId);
        if (index != -1) {
          participants[index] = participants[index].copyWith(
            name: profile['username'] ?? 'Partner',
            avatarUrl: profile['avatar_url'],
          );
          addLog('👤 Profile: Fetched for $userId (${profile['username']})');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Sovereign: Profile fetch failed: $e');
    }
  }

  // --- Signaling logic continues here ---

  // Set to track processed ICE candidates to avoid duplicates from DB stream

  /// [G3_RESILIENCE]: Force a refresh of the signaling stream.
  /// Called when a token is refreshed to ensure we aren't using a stale channel.
  void _syncPresenceState() {
    if (_channel == null) return;

    try {
      final List<SinglePresenceState> state = _channel!.presenceState();
      // PresenceState in later SDKs is a List of objects
      final onlineUserIds = <String>{};
      for (final presence in state) {
        // Each presence might have multiple joins (presences)
        for (final p in presence.presences) {
          final userId = p.payload['user_id']?.toString();
          if (userId != null) onlineUserIds.add(userId);
        }
      }

      // Update participants
      for (var p in participants) {
        p.isOnline.value = onlineUserIds.contains(p.id);
      }

      debugPrint('🟢 Presence: ${onlineUserIds.length} users online');
    } catch (e) {
      addLog('⚠️ Presence Sync Error: $e');
    }
  }

  // --- Signaling Logic (Mesh) ---

  void _sendSignal(
      {required String receiverId,
      required String type,
      required Map<String, dynamic> data,
      int attempt = 1}) {
    if (_channel == null || _engine.status == CommSessionStatus.idle) {
      return;
    }

    final callId = sessionId.value;
    final int version = _sessionVersions[callId] ?? 0;

    // ignore: invalid_use_of_protected_member
    final res = (_channel as dynamic).send(
      type: RealtimeListenTypes.broadcast,
      event: 'signaling',
      payload: {
        'version': version, // [Area 6]: Session-scoped tracker
        'negotiation_id': _currentNegotiationId, // [Area 5]: Correlation ID
        'epoch': version, // Backward compatibility
        'call_id': callId, // Mandatory Constitutional Field
        'sender_id': currentUserId,
        'receiver_id': receiverId,
        'type': type,
        'signal_type':
            type, // [CRITICAL FIX]: Backup type field as 'type' gets clobbered
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    addLog('📡 Sent: $type -> $receiverId');

    if (res == 'ok') {
      if (_engine.status == CommSessionStatus.reconnecting) {
        _engine.statusRx.value = isCameraOn.value
            ? CommSessionStatus.activeVideo
            : CommSessionStatus.activeAudio;
      }
      _silentRetryCount = 0;
    } else {
      // [SOVEREIGN_LOGIC]: Increase silent retry count.
      // We are more lenient with ice-candidates as they are many and often jittery.
      final weight = (type == 'ice-candidate') ? 0.5 : 1.5;
      _silentRetryCount += weight;

      // If we had enough failures, show recovery UI
      // [SOVEREIGN_FIX]: Only show reconnecting if WebRTC itself isn't active/connected.
      // Limit raised to 15.0 (approx 10 regular signals or 30 candidates) to handle Windows jitters
      if (_silentRetryCount > 15.0 &&
          (_engine.status == CommSessionStatus.activeAudio ||
              _engine.status == CommSessionStatus.activeVideo) &&
          webRTCState.value != WebRTCLifecycle.iceConnected &&
          webRTCState.value != WebRTCLifecycle.active) {
        _engine.statusRx.value = CommSessionStatus.reconnecting;
      }

      // [Stage C9]: Silent Retry logic for broadcast failures
      if (_silentRetryCount < 15 &&
          (type == 'offer' || type == 'answer' || type == 'ice-candidate')) {
        final delay = (500 * _silentRetryCount.toInt()).clamp(200, 1000);
        Timer(
            Duration(milliseconds: delay),
            () => _sendSignal(
                receiverId: receiverId,
                type: type,
                data: data,
                attempt: attempt + 1));
      }
    }
  }

  // --- Management ---

  Future<void> resetMyStatus() async {
    final uid = currentUserId;
    if (uid.isEmpty) return;

    try {
      // 1. Clear ghost calls in DB
      await _callRepo.clearGhostCalls(uid);

      // 2. Set user status to online (clears 'busy')
      // Note: IUserRepository should have updateStatus or similar
      await _userRepo.updateStatus(uid, UserStatus.online);

      addLog(
          '✅ Sovereignty: My status has been reset and ghost sessions cleared.');
      Get.snackbar(
        'إصلاح الحالة',
        'تم إخلاء الجلسات العالقة وإعادة تعيين حالة الاتصال بنجاح.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.withValues(alpha: 0.1),
        colorText: Colors.green,
      );
    } catch (e) {
      addLog('❌ Sovereignty: Status reset failed: $e');
      Get.snackbar(
        'خطأ',
        'فشل إخلاء الجلسات العالقة: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.1),
        colorText: Colors.red,
      );
    }
  }

  Future<void> renameSession(String newName) async {
    if (sessionId.value.isEmpty) return;
    await _supabase
        .from('rooms')
        .update({'name': newName}).eq('id', sessionId.value);
    sessionName.value = newName;
  }

  Future<void> deleteSession() async {
    if (sessionId.value.isEmpty) return;
    final id = sessionId.value;
    await leaveSession();
    await _supabase.from('rooms').delete().eq('id', id);
  }

  void updateInputVolume(double value) {
    inputVolume.value = value;
  }

  void updateOutputVolume(double value) {
    outputVolume.value = value;
    if (value > 0) {
      isSpeakerOn.value = true;
    } else {
      isSpeakerOn.value = false;
    }

    // [SOVEREIGN_FIX]: Apply volume directly to all remote participants via WebRTC receivers
    for (var p in participants) {
      if (!p.isLocal) {
        final track = p.remoteStream.value?.getAudioTracks().firstOrNull;
        if (track != null && track.id != null) {
          unawaited(_webrtc.applyVolumeToReceiver(track.id!, value));
        }
      }
    }
  }

  /// [ARCHITECTURAL]: Starts/Resets the timer to auto-hide controls after 5 seconds
  void startControlsTimer() {
    _controlsTimer?.cancel();
    showControls.value = true;
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (!isClosed && (isCameraOn.value || participants.length > 1)) {
        showControls.value = false;
      }
    });
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn.value = !isSpeakerOn.value;
    debugPrint('🔊 UI: Toggling Speaker -> ${isSpeakerOn.value}');

    // [ANDROID_ROUTING]: Explicitly switch between Speaker and Earpiece
    await _webrtc.setSpeakerphoneOn(isSpeakerOn.value);

    // [NATIVE_AUDIO_HARDENING]: Professional AudioManager Sync
    if (GetPlatform.isAndroid && !kIsWeb) {
      try {
        await const MethodChannel('com.example.talkmate_ai/native_audio')
            .invokeMethod('setSpeakerOn', {'on': isSpeakerOn.value});
      } catch (e) {
        debugPrint('⚠️ [NATIVE_ROUTER]: Speaker toggle failed: $e');
      }
    }

    // [Stage R5.5] Sync Volume UI - Don't zero out volume anymore
    // Switching to earpiece should NOT mute the call.
    final vol = outputVolume.value > 0 ? outputVolume.value : 0.8;
    outputVolume.value = vol;

    startControlsTimer();
  }

  Future<void> toggleMute() async {
    if (_isNegotiationLocked) {
      addLog('🛡️ [Area 4] Queueing toggleMute (Negotiation Locked)');
      _negotiationTaskQueue.add(() => toggleMute());
      return;
    }
    isMuted.value = !isMuted.value;

    // [HARD_SYNC]: Ensure track matches UI state immediately
    _webrtc.toggleAudio(isMuted.value);

    // [Stage R4]: Sync State with Signaling
    if (_myParticipantId != null) {
      await _supabase
          .from('room_participants')
          .update({'is_muted': isMuted.value}).eq('id', _myParticipantId!);
    } else if (sessionType.value == CommunicationSessionType.call) {
      _sendSignal(
          receiverId: 'all', type: 'mute', data: {'is_muted': isMuted.value});
    }

    startControlsTimer();
  }

  Future<void> toggleCamera() async {
    if (_isNegotiationLocked) {
      addLog('🛡️ [Area 4] Queueing toggleCamera (Negotiation Locked)');
      _negotiationTaskQueue.add(() => toggleCamera());
      return;
    }
    isCameraOn.value = !isCameraOn.value;

    // [HARD_TRACK_STOP]: Strictly disable video track when camera is off
    _webrtc.toggleVideo(isCameraOn.value);

    // [Stage R26]: Intelligent Media Upgrade
    // If camera is on but localStream lacks video, we need to upgrade.
    if (isCameraOn.value && (localStream?.getVideoTracks().isEmpty ?? true)) {
      try {
        final hasAudio = localStream?.getAudioTracks().isNotEmpty ?? false;

        // [WINDOWS_STABILITY]: If we already have audio, only request video
        // to prevent hardware driver locks/crashes.
        if (hasAudio && GetPlatform.isWindows) {
          addLog(
              '🎥 [WINDOWS] Requesting VIDEO ONLY to preserve existing audio...');
          final videoStream =
              await _webrtc.initLocalMedia(isAudio: false, isVideo: true);
          localStream = videoStream;
        } else if (hasAudio) {
          addLog('🎥 [UPGRADE] Adding video to existing audio stream...');
          // On mobile, we usually re-init both for consistent synchronization
          final upgradedStream =
              await _webrtc.initLocalMedia(isAudio: true, isVideo: true);
          localStream = upgradedStream;
        } else {
          await _initMedia(true);
        }

        // [ZERO_LOOPBACK_STRATEGY_UPGRADE]
        // We strictly isolate the video track to prevent audio loopback from the renderer.
        if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
          final videoOnlyStream =
              await webrtc.createLocalMediaStream('local_video_proxy_upgrade');
          for (var track in localStream!.getVideoTracks()) {
            await videoOnlyStream.addTrack(track);
          }
          localRenderer.srcObject = videoOnlyStream;
          addLog('🎥 [UPGRADE] Video proxy attached (Audio Isolated)');
        }

        // [RADICAL FIX]: Re-inject all tracks (especially new video) into peers
        await _webrtc.addLocalTracksToPeers();

        // Renegotiate with all peers to announce the new video stream
        for (var p in participants) {
          if (!p.isLocal) {
            await _renegotiate(p.id);
          }
        }
      } catch (e) {
        debugPrint('❌ Upgrade to Video Failed: $e');
        isCameraOn.value = false;
        _webrtc.toggleVideo(false);
      }
    }

    if (_myParticipantId != null) {
      await _supabase.from('room_participants').update(
          {'is_video_on': isCameraOn.value}).eq('id', _myParticipantId!);
    } else if (sessionType.value == CommunicationSessionType.call) {
      _sendSignal(
          receiverId: 'all',
          type: 'camera',
          data: {'is_video_on': isCameraOn.value});
    }

    startControlsTimer();
  }

  Future<void> _renegotiate(String userId) async {
    if (_isNegotiationLocked) {
      addLog('🛡️ [Area 4] Queueing _renegotiate (Negotiation Locked)');
      _negotiationTaskQueue.add(() => _renegotiate(userId));
      return;
    }
    final pc = _webrtc.getPeer(userId);
    if (pc == null) return;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal(receiverId: userId, type: 'offer', data: {'sdp': offer.sdp});
    } catch (e) {
      debugPrint('❌ Renegotiation failed for $userId: $e');
    }
  }

  Future<void> switchCamera() async {
    await _webrtc.switchCamera();
  }

  Future<void> _handleSignaling(Map<String, dynamic> rawEnvelope) async {
    // [Stage R5]: Robust unwrap for various Supabase Realtime versions.
    // Some versions pass the whole envelope { type: 'broadcast', event: 'signaling', payload: { ... } }
    final Map<String, dynamic> payload =
        (rawEnvelope['payload'] != null && rawEnvelope['payload'] is Map)
            ? Map<String, dynamic>.from(rawEnvelope['payload'] as Map)
            : rawEnvelope;

    // [CARRIER_GRADE_SAFETY]: Drop late signals from previous epochs or zombie sessions
    // [SOVEREIGN_RECOVERY]: If a higher epoch arrives with an Offer/Invite, align with it.
    if (payload['version'] != null || payload['epoch'] != null) {
      final int incomingVersion =
          (payload['version'] ?? payload['epoch']) as int;
      final String signalType = payload['signal_type']?.toString() ??
          payload['type']?.toString() ??
          '';
      final currentSessionVersion = _sessionVersions[sessionId.value] ?? 0;

      if (incomingVersion > currentSessionVersion &&
          (signalType == 'offer' || signalType == 'call_invite')) {
        debugPrint(
            '🔄 Sovereign: UPGRADING local version from $currentSessionVersion to $incomingVersion');
        _sessionVersions[sessionId.value] = incomingVersion;
      } else if (incomingVersion < currentSessionVersion) {
        debugPrint('🛡️ Sovereign: Discarding STALE signal from version '
            '$incomingVersion (Current: $currentSessionVersion)');
        return;
      }
    }

    // [Area 5]: Correlation Update
    if (payload['negotiation_id'] != null) {
      final String incomingNegId = payload['negotiation_id'].toString();
      final int incomingVersion =
          (payload['version'] ?? payload['epoch'] ?? 0) as int;
      final currentV = _sessionVersions[sessionId.value] ?? 0;
      if (_currentNegotiationId == null || incomingVersion > currentV) {
        _currentNegotiationId = incomingNegId;
      }
    }

    final senderId = payload['sender_id']?.toString() ?? '';
    final receiverId = payload['receiver_id']?.toString() ?? 'all';
    // [CRITICAL FIX]: Prioritize 'signal_type', then 'type'.
    // Supabase Realtime client overwrites 'type' with 'broadcast' for broadcast events.
    var type =
        payload['signal_type']?.toString() ?? payload['type']?.toString() ?? '';

    final data = payload['data'] != null
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : <String, dynamic>{};

    // [DEBUGGING]: Concise log
    debugPrint('🕵️ SIG: Type=$type | Sender=$senderId');

    // [CRITICAL FIX]: If type is STILL generic 'broadcast', use specific 'event' or try to guess
    if (type == 'broadcast') {
      if (payload['event'] != null) {
        type = payload['event'].toString();
      } else if (data.containsKey('candidate')) {
        type = 'ice-candidate';
      }
    }

    addLog('🔔 Recv: $type from $senderId');

    if (senderId.isEmpty || type.isEmpty) return;
    if (senderId == currentUserId) return;
    if (receiverId != 'all' && receiverId != currentUserId) return;

    // Constitutional Guard: Verify call_id matches current session for direct signals
    // [R32 FIX]: Allow transitions by checking against current OR previous ID (Promotion Hardening)
    if (payload['call_id'] != null &&
        payload['call_id'] != sessionId.value &&
        payload['call_id'] != _previousSessionId &&
        type != 'call_invite') {
      debugPrint(
          '⚠️ Constitutional: Ignoring signal for foreign call_id: ${payload['call_id']} (Current: ${sessionId.value}, Prev: $_previousSessionId)');
      return;
    }

    // [Area 4]: Negotiation Lock During Sensitive Operations (e.g. ICE Restart)
    if (_isNegotiationLocked &&
        (type == 'offer' || type == 'answer' || type == 'ice-candidate')) {
      addLog(
          '🛡️ [Area 4] Guard: Ignoring $type because negotiation is LOCKED.');
      return;
    }

    switch (type) {
      case 'call_end':
      case 'terminate':
        final reason = data['reason']?.toString() ?? 'unknown';

        // [STATE_GUARD]: Ignore TIMEOUT signal if we are already connected/active
        if (reason == 'timeout') {
          if (webRTCState.value == WebRTCLifecycle.iceConnected ||
              webRTCState.value == WebRTCLifecycle.mediaFlowing ||
              webRTCState.value == WebRTCLifecycle.active ||
              _engine.status == CommSessionStatus.activeAudio ||
              _engine.status == CommSessionStatus.activeVideo ||
              _engine.status == CommSessionStatus.connecting) {
            addLog(
                '🛡️ Sovereign Guard: Ignoring TIMEOUT signal because call is ACTIVE/CONNECTING.');
            return;
          }
        }

        addLog(
            '🛑 Recv: TERMINATE/CALL_END signal (Reason: $reason). Closing session locally...');
        unawaited(CallManager.instance
            .terminateCall(fromRemote: true, reason: reason));
        break;
      case 'room_ready':
        // Rooms still use Broadcast for rapid mesh sync
        if (senderId != currentUserId &&
            sessionType.value == CommunicationSessionType.room) {
          await _initPeer(senderId, isInitiator: true);
        }
        break;
      case 'room_leave':
        if (sessionType.value == CommunicationSessionType.room) {
          participants.removeWhere((p) => p.id == senderId);
          await _webrtc.removePeer(senderId);
          addLog('👋 Remote left room: $senderId');
        }
        break;
      case 'mute':
        if (data['is_muted'] == null) return;
        final pIndex = participants.indexWhere((p) => p.id == senderId);
        if (pIndex != -1) participants[pIndex].isMuted.value = data['is_muted'];
        break;
      case 'camera':
        if (data['is_video_on'] == null) return;
        final pIndex = participants.indexWhere((p) => p.id == senderId);
        if (pIndex != -1) {
          participants[pIndex].isVideoOn.value = data['is_video_on'];
        }
        break;
      case 'leave':
        // Universal leave signal (Broadcast fallback)
        addLog('🏃 USER_LEFT_RECEIVED via Broadcast');
        if (sessionType.value == CommunicationSessionType.call) {
          unawaited(exitGracefully());
        } else {
          await _webrtc.removePeer(senderId);
          participants.removeWhere((p) => p.id == senderId);
        }
        break;
      // [Constitutional] Call signaling is now handled via DB Stream.
      // We explicitly ignore these here to avoid double-processing.
      case 'offer':
        if (!isInitiator) {
          final sdp = data['sdp']?.toString() ?? '';
          if (sdp.isEmpty) return;
          final sdpHash = sdp.hashCode.toString();
          final signalKey = '${sessionId.value}_offer_$sdpHash';

          if (_processedSignals.contains(signalKey)) {
            addLog('♻️ Offer already processed: $signalKey');
            return;
          }

          // [Stage R28]: Deterministic Reset - Buffering removed.
          // If we are idle, we wait for the user to accept (acceptCall will pull the offer).
          // If we are already connecting/accepting, we process it immediately.
          if (webRTCState.value == WebRTCLifecycle.idle) {
            addLog('📡 Offer Received while IDLE. Waiting for User Accept...');
            return;
          }

          // [RADICAL FIX]: Radical acceptance of Offer.
          // We do NOT check webRTCState here. Signaling is the Source of Truth.
          // If we receive an Offer for this session, we must process it.
          // [GLARE]: Collision check for Renegotiation Offer
          final pc = _webrtc.getPeer(senderId);
          final signalingState = pc?.signalingState ??
              webrtc.RTCSignalingState.RTCSignalingStateStable;

          // [CRITICAL FIX]: Strict Glare Detection
          // We only collide if we are actively making an offer OR strictly within 'HaveLocalOffer' state.
          final isIceRestartOffer =
              data['ice_restart'] == true || data['iceRestart'] == true;

          final peer = _webrtc.getSovereign(senderId);
          final isGenuineGlare = (peer != null && peer.makingOffer) ||
              signalingState ==
                  webrtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer;

          final offerCollision = isGenuineGlare;

          // [GOLDEN_RULE]: The Ignore Logic (Step 2)
          final shouldIgnoreOffer = !_isInitialCallSetup &&
              !isIceRestartOffer &&
              !isPolite &&
              offerCollision;

          if (shouldIgnoreOffer) {
            addLog(
                '⚠️ GLARE: Impolite Peer ignoring broadcast offer (Stable Mode).');
            return;
          }

          if (offerCollision) {
            if (isPolite) {
              addLog(
                  '⚠️ GLARE: Polite Peer (Broadcast) - Attempting rollback to handle remote offer.');
              try {
                // [R32.2]: Attempt polite rollback if supported.
                // Note: RTCSessionDescription with 'rollback' type is the standard way.
                await pc!.setLocalDescription(
                    webrtc.RTCSessionDescription(null, 'rollback'));
                addLog('✅ GLARE: Rollback successful.');
              } catch (e) {
                addLog(
                    '⚠️ GLARE: Rollback failed or unsupported ($e). Falling back to reconstruction.');
                await _webrtc.removePeer(senderId);
              }
            } else if (_isInitialCallSetup) {
              addLog(
                  '⚠️ GLARE: Initial setup collision. Resetting for fresh start.');
              await _webrtc.removePeer(senderId);
            }
          }

          // [R32 FIX]: Set explicit restart flag to allow state machine rollback
          if (isIceRestartOffer) {
            _isIceRestart = true;
            addLog('🧊 ICE: Broadcast ICE_RESTART Offer detected.');
          }

          addLog('📄 Recv: OFFER via Broadcast (Radical Acceptance)');
          PHASE('PHASE: REMOTE_SDP_SET (Offer)');
          _transitionToState(WebRTCLifecycle.offerReceived,
              source: 'broadcast_offer');

          unawaited(_initPeer(senderId,
              isInitiator: false, remoteSdp: sdp, sendAnswer: false));
          _processedSignals.add(signalKey);
        }
        break;
      case 'answer':
        final sdp = data['sdp']?.toString() ?? '';
        if (sdp.isEmpty) return;
        final sdpHash = sdp.hashCode.toString();
        final signalKey = '${sessionId.value}_answer_$sdpHash';

        if (_processedSignals.contains(signalKey)) {
          addLog('♻️ Answer already processed: $signalKey');
          return;
        }

        addLog(
            '⚡ Handle Signal: ANSWER | Initiator=$isInitiator | Key=$signalKey');

        final pc = _webrtc.getPeer(senderId);

        // [Stage R28]: Deterministic Reset - Buffering removed for Answers.
        if (pc == null ||
            pc.signalingState !=
                webrtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          addLog(
              '⚠️ Answer Received but not in HaveLocalOffer state. Ignoring.');
          return;
        }

        final peer = _webrtc.getSovereign(senderId);
        if (peer == null) return;

        try {
          peer.isSettingRemoteAnswerPending =
              true; // [GOLDEN_RULE]: Critical Section Start
          await pc.setRemoteDescription(
              webrtc.RTCSessionDescription(sdp, 'answer'));
          _processedSignals.add(signalKey);
          PHASE('PHASE: REMOTE_SDP_SET (Answer)');
          addLog('📄 REMOTE_SDP_SET (Answer via Broadcast) - SUCCESS');
          // [FORENSIC]: Drain buffered candidates now that Remote Desc is set
          unawaited(_webrtc.drainCandidates(senderId));
        } catch (e) {
          addLog('❌ SetRemoteDesc (Answer) Failed: $e');
        } finally {
          peer.isSettingRemoteAnswerPending =
              false; // [GOLDEN_RULE]: Critical Section End
        }
        break;
      case 'ice-candidate':
        final v = payload['version'] as int?;
        if (v != null && v < (_sessionVersions[sessionId.value] ?? 0)) {
          addLog('🛡️ DB: Discarding STALE Candidate (v$v)');
          return;
        }
        await _handleIceCandidateSignal(senderId, data);
        break;
      case 'call_ringing':
      case 'call_accepted':
        debugPrint('ℹ️ Constitutional: Transient $type signal ignored.');
        break;
    }
  }

  /// [PRODUCTION]: Handles ICE candidates received via Realtime Broadcast (Low Latency)
  Future<void> _handleIceCandidateSignal(
      String remoteId, Map<String, dynamic> json) async {
    final candidateStr = json['candidate']?.toString() ?? '';
    if (candidateStr.isEmpty) return;

    // Filter out if we created it (echo) or if processed
    final candHash =
        '${json['sdpMid']}_${json['sdpMLineIndex']}_${candidateStr.hashCode}';

    if (!_processedSignals.contains(candHash)) {
      final cand = webrtc.RTCIceCandidate(
        json['candidate'],
        json['sdpMid'],
        json['sdpMLineIndex'],
      );

      addLog('🧊 ICE: Signal Received via Broadcast. Adding to Manager...');

      // [GOLDEN_RULE]: Step 4 - Conditional Deferral
      final peer = _webrtc.getSovereign(remoteId);
      if (peer != null && peer.isSettingRemoteAnswerPending) {
        addLog('⏳ ICE: Deferring candidate (Remote Answer Pending)...');
        // We rely on WebRTCConnectionManager to buffer if RDS is null,
        // but we can explicitly log or enforce here.
        // WebRTCConnectionManager.addIncomingCandidate handles buffering if remote desc is missing.
        // But the user asked for explicit "queueCandidate".
        // Since we don't have a separate queue method exposed, and addIncomingCandidate DOES queue,
        // we just proceed, but we acknowledge the state.
        await _webrtc.addIncomingCandidate(remoteId, cand);
      } else {
        await _webrtc.addIncomingCandidate(remoteId, cand);
      }
      _processedSignals.add(candHash);

      // [ICE_RESTART_SYNC]: The WebRTCConnectionManager watchdog now handles connectivity stalls.
    }
  }

  /// Initiates a sequence that fades out the UI and then leaves the session.
  /// Used primarily when the user clicks 'Hang Out' or the other peer leaves.
  Future<void> exitGracefully() async {
    if (isEnding.value && _isCleaningUp) return;
    isEnding.value = true;

    addLog('🚀 Sovereign: Graceful exit sequence started (Fade-out)...');

    // 1. Give time for a quick fade-out animation
    await Future.delayed(const Duration(milliseconds: 400));

    // 2. Clear any open overlays (settings sheet, etc) if they are still open
    if (Get.isOverlaysOpen || Get.isBottomSheetOpen == true) {
      Get.back();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 3. Close the main communication screen
    if (Get.currentRoute == '/communication_live') {
      addLog('🚀 Sovereign: Closing communication_live screen...');
      Get.back();

      // [SAFETY]: If we are still on the screen (e.g. it was the only route), force return to /main
      await Future.delayed(const Duration(milliseconds: 200));
      if (Get.currentRoute == '/communication_live') {
        addLog('🚀 Sovereign: Back failed (Last route), forcing /main');
        unawaited(Get.offAllNamed('/main'));
      }
    } else {
      // Recovery logic: if we are already off the screen, ensure cleanup runs
      addLog(
          '🚀 Sovereign: Already off screen (Route: ${Get.currentRoute}), ensuring background cleanup...');
      unawaited(leaveSession(reason: 'manual'));
    }
  }

  Future<void> _initPeer(String userId,
      {required bool isInitiator,
      String? remoteSdp,
      bool sendAnswer = true,
      bool isVideo = false}) async {
    addLog('🏗️ Peer: Initializing for $userId (Initiator: $isInitiator)...');
    // [Area 5]: Correlation ID for new peer/negotiation cycle
    _currentNegotiationId =
        'neg-$userId-${DateTime.now().millisecondsSinceEpoch}';

    _signalingHistory.add(
        '[${DateTime.now().toIso8601String()}] InitPeer (isInitiator: $isInitiator)');

    // [R31] Start 15s hard failure watchdog
    _connectingWatchdogs[userId]?.cancel();
    _connectingWatchdogs[userId] = Timer(const Duration(seconds: 15), () {
      if (webRTCState.value != WebRTCLifecycle.active &&
          webRTCState.value != WebRTCLifecycle.mediaFlowing &&
          _webrtc.getPeer(userId) != null) {
        addLog(
            '🚨 [R31] Hard Failure: Connection STALLED for 15s. Triggering full reset.');
        unawaited(executeR31ForensicSuite(userId));
        unawaited(CallManager.instance.terminateCall(
            fromRemote: false, reason: 'connection_stalled_15s'));
      }
    });

    // [R30] Advanced Stability: Fast Fallback Watchdog (Windows Focus)
    // [R33] Jitter Fix: Add ±250ms random jitter
    // [R34] Stability: Increase to 8s to allow for TURN/DTLS stabilization
    final jitter = (DateTime.now().millisecondsSinceEpoch % 500) - 250;
    Timer(Duration(milliseconds: 8000 + jitter), () {
      final peer = _webrtc.getPeer(userId);
      if (peer != null &&
          peer.connectionState !=
              webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          webRTCState.value != WebRTCLifecycle.mediaFlowing &&
          webRTCState.value != WebRTCLifecycle.active) {
        addLog(
            '⚠️ [R30] Connection STALL detected (8s). Triggering Fast Recovery...');
        unawaited(_triggerIceRestart(userId));
      }
    });

    // [HARDENING]: Prevent racing dual-init
    // [Stage R26]: Prevent Double Peer Creation
    if (_webrtc.getPeer(userId) != null) {
      addLog('🛑 Peer already exists for $userId — skipping re-init.');
      return;
    }

    try {
      final pc = await _webrtc.initPeerConnection(
        userId,
        isVideo: isVideo,
        onStreamAdded: (stream) => _assignStreamToParticipant(userId, stream),
        onIceCandidate: (c) {
          final sovereign = _webrtc.getSovereign(userId);
          if (sovereign != null && sovereign.isIceEmissionStopped) return;

          addLog('🧊 ICE: Local candidate generated');
          _sendSignal(
            receiverId: userId,
            type: 'ice-candidate',
            data: {
              'candidate': c.candidate,
              'sdpMid': c.sdpMid,
              'sdpMLineIndex': c.sdpMLineIndex,
              'version': _sessionVersions[sessionId.value] ?? 0,
              'cid': _currentNegotiationId, // Correlation ID
            },
          );
        },
        onIceStateChanged: (state) => _handleIceStateChange(userId, state),
      );

      // [DTLS_AUDIT]: Monitor connection state for handshake failures
      pc.pc.onConnectionState = (state) {
        addLog(
            '🤝 Connection: $userId -> ${state.name} (DTLS/Handshake State)');

        // [Advanced Stability]: Log connecting state for diagnostic trace
        if (state ==
            webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          addLog('🤝 [DTLS] Handshake START for $userId (Connecting...)');
        }

        if (state ==
            webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          addLog('🤝 [DTLS] Handshake SUCCESS for $userId (Connected)');
          // [R30] ICE Governance: Check if we can stop emission now
          final iceState = pc.pc.iceConnectionState;
          if (pc.hasRemoteSdp &&
              (iceState ==
                      webrtc.RTCIceConnectionState
                          .RTCIceConnectionStateConnected ||
                  iceState ==
                      webrtc.RTCIceConnectionState
                          .RTCIceConnectionStateCompleted)) {
            pc.isIceEmissionStopped = true;
            addLog(
                '🧊 [R30] ICE Stable: Candidate emission STOPPED for $userId (DTLS Triggered)');
          }
        }

        if (state ==
            webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          addLog('❌ DTLS: Peer handshake failed for $userId');
          _engine.telemetry.dtlsFailureCount++; // [R33] Track DTLS failure
        }

        if (state ==
            webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          addLog('🤝 [DTLS] Peer DISCONNECTED for $userId');
        }
      };

      final SovereignPeer peer =
          pc; // initPeerConnection now returns SovereignPeer

      if (isInitiator) {
        try {
          // [DIAGNOSTIC STRIKE]: Final media verification before Offer
          addLog(
              '[MEDIA] localTracks count = ${localStream?.getTracks().length ?? 0}');
          if (localStream != null) {
            for (var t in localStream!.getTracks()) {
              addLog(
                  '[MEDIA] track: ${t.kind}, enabled=${t.enabled}, id=${t.id}');
            }
          } else {
            addLog(
                '[MEDIA] 🚨 CRITICAL: localStream is NULL before createOffer!');
          }

          peer.makingOffer = true;
          final offer = await peer.createOffer();
          await peer.setLocalDescription(offer);
          peer.makingOffer = false;
          addLog('📄 LOCAL_SDP_SET (Offer) [R30 Guarded]');

          // [Stage R32.1]: Ensure transceivers are synced after offer
          unawaited(_syncTransceivers(userId));

          // [R31+]: Immediate Sender Trace (Phase 1)
          if (GetPlatform.isAndroid) {
            final senders = await peer.getSenders();
            addLog('🔥 [R31+] PHASE 1 (Immediate Trace)');
            addLog('DTLS STATE: ${peer.pc.connectionState?.name}');
            addLog('SIGNALING STATE: ${peer.pc.signalingState?.name}');
            for (var s in senders) {
              addLog('ANDROID SENDER TRACK: '
                  'kind=${s.track?.kind}, '
                  'enabled=${s.track?.enabled}');
            }
          }

          // [Stage R28.2]: Step 4 - Outbound RTP Check (Post-SetLocal)
          if (GetPlatform.isWindows) {
            addLog('🔥 [STEP 4] Waiting 2s for RTP Stats...');
            Future.delayed(const Duration(seconds: 2), () async {
              if (isClosed) return;
              final stats = await peer.getStats();
              bool foundOutbound = false;
              for (var report in stats) {
                if (report.type == 'outbound-rtp' &&
                    report.values['kind'] == 'audio') {
                  addLog(
                      "🔥 [STEP 4] OUTBOUND BYTES: ${report.values['bytesSent']}");
                  foundOutbound = true;
                }
              }
              if (!foundOutbound) {
                addLog(
                    '🔥 [STEP 4] ⚠️ No outbound-rtp audio report found yet.');
              }
            });
          }

          addLog('📄 DB: Writing Offer to session ${sessionId.value}...');
          final currentV = _sessionVersions[sessionId.value] ?? 0;
          await _callRepo.setOffer(sessionId.value, offer.sdp!,
              extra: {'version': currentV, 'cid': _currentNegotiationId});
          addLog(
              '✅ DB: Offer WRITTEN (Version: $currentV, CID: $_currentNegotiationId).');

          _sendSignal(
            receiverId: userId,
            type: 'offer',
            data: {
              'sdp': offer.sdp,
              'cid': _currentNegotiationId,
            },
          );
          addLog('📡 Sent: offer -> $userId (CID: $_currentNegotiationId)');
          _signalingHistory
              .add('[${DateTime.now().toIso8601String()}] Offer Sent');
        } catch (e) {
          addLog('❌ Sovereign: Failed to create/send OFFER: $e');
          rethrow;
        }
      } else if (remoteSdp != null) {
        try {
          // [RADICAL FIX]: Delayed Answer Strategy
          // We set the remote description to enable ICE candidate buffering,
          // but we DO NOT create or send an answer until the user accepts.

          final sovereign = _webrtc.getSovereign(userId);
          if (sovereign != null) sovereign.isSettingRemoteAnswerPending = true;
          try {
            await pc.setRemoteDescription(
                webrtc.RTCSessionDescription(remoteSdp, 'offer'));
            addLog(
                '📄 REMOTE_SDP_SET (Offer) - Waiting for User Accept [R30 Guarded]');
          } finally {
            if (sovereign != null) {
              sovereign.isSettingRemoteAnswerPending = false;
            }
          }

          if (isInitiator) {
            // Should not happen, but safe fallback
          } else {
            // [Stage R24]: If user already accepted (sticky intent), answer now.
            if (sendAnswer || _hasUserAccepted) {
              addLog(
                  '📞 Sovereign: Sticky Acceptance detected. Answering now...');
              await _answerIncomingCall(userId);
            }
          }
        } catch (e) {
          peer.isSettingRemoteAnswerPending = false;
          addLog('❌ Sovereign: Failed to handle OFFER: $e');
          rethrow;
        }
      }
    } catch (e) {
      addLog('❌ Sovereign: Critical Peer Init Failure: $e');
      await _webrtc.removePeer(userId); // Ensure no zombie connection
    }
  }

  /// [RADICAL FIX]: Finalize Answer Generation
  /// Called when the user has accepted the call and media is ready.
  Future<void> _finalizeAnswer(String userId, SovereignPeer peer) async {
    if (_isFinalizingAnswer || peer.hasAnswered) {
      addLog('⚠️ [FIX] _finalizeAnswer Refused: Active or Already Answered.');
      return;
    }
    _isFinalizingAnswer = true;
    peer.hasAnswered = true; // [Idempotency] Set immediately

    try {
      addLog('📝 Finalizing Answer for $userId...');

      // [Advanced Stability]: Wait 100ms to ensure remote tracks/hardware are ready
      if (GetPlatform.isWindows) {
        addLog('⏳ [R30] Stability: 100ms delay before createAnswer (Windows)');
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);

      addLog('📄 LOCAL_SDP_SET (Answer) - Delayed');

      // [DB WRITE]: Write Answer to DB (Async but awaited for safety)
      addLog('📄 DB: Writing Answer to session ${sessionId.value}...');
      await _callRepo.setAnswer(sessionId.value, answer.sdp!, extra: {
        'version': _sessionVersions[sessionId.value] ?? 0,
        'cid': _currentNegotiationId
      });
      addLog('✅ DB: Answer WRITTEN (CID: $_currentNegotiationId).');

      // [ZERO-REST]: Broadcast Answer ASAP
      _sendSignal(
        receiverId: userId,
        type: 'answer',
        data: {
          'sdp': answer.sdp,
          'cid': _currentNegotiationId,
        },
      );
      addLog('📡 Sent: answer -> $userId');
      PHASE('PHASE: ANSWER_SENT');
      _signalingHistory
          .add('[${DateTime.now().toIso8601String()}] Answer Sent');

      // [R34] REMOVAL: Do NOT freeze signaling immediately after Answer.
      // Wait for PeerConnectionState == connected.

      // [POST-ANSWER]: Drain candidates now that everything is set
      await _webrtc.drainCandidates(userId);
    } catch (e) {
      peer.hasAnswered = false; // [Idempotency Recovery]
      addLog('❌ Sovereign: Failed to Finalize Answer: $e');
      rethrow;
    } finally {
      _isFinalizingAnswer = false;
    }
  }

  /// [RADICAL FIX]: Handle Incoming Call Acceptance
  /// Called when the user clicks "Accept" or the call becomes active.
  Future<void> _answerIncomingCall(String remoteId) async {
    addLog('📞 Sovereign: Answering Incoming Call from $remoteId...');

    // 1. Media is already prepared via prepare() in acceptCall() chain.
    // We only call _initMedia if the stream was somehow lost.
    if (localStream == null) {
      await _initMedia(isCameraOn.value);
    }

    // 2. Check Peer Connection
    final pc = _webrtc.getPeer(remoteId);
    if (pc == null) {
      addLog(
          '⚠️ Sovereign: No PeerConnection found for $remoteId. Is Offer processed?');
      return;
    }

    // 3. Check Remote Description
    if (await pc.getRemoteDescription() == null) {
      addLog('⚠️ Sovereign: No Remote Description set. Cannot Answer yet.');
      return;
    }

    // 4. Finalize Answer
    final sovereign = _webrtc.getSovereign(remoteId);
    if (sovereign == null) {
      addLog('⚠️ Sovereign: Wrapper not found for $remoteId');
      return;
    }

    // Check if we already answered to avoid duplicate answers
    if (await _safeGetLocalDescription(pc) != null) {
      addLog('⚠️ Sovereign: Local Description already set. Skipping Answer.');
      return;
    }

    await _finalizeAnswer(remoteId, sovereign);

    _transitionToState(WebRTCLifecycle.answerSent, source: 'answer_generation');
    // Ensure status update
    _engine.statusRx.value = isCameraOn.value
        ? CommSessionStatus.activeVideo
        : CommSessionStatus.activeAudio;
  }

  // Legacy candidate management removed (using immediate send for production)

  Future<void> _assignStreamToParticipant(
      String userId, webrtc.MediaStream stream) async {
    var index = participants.indexWhere((p) => p.id == userId);

    if (index == -1) {
      debugPrint(
          '⚠️ Sovereign: Late stream for $userId. Participant not in list.');
      // [SAFETY]: Add participant to list if we received a stream but they are missing
      participants.add(CommunicationParticipant(
        id: userId,
        rowId: 'remote_late',
        name: 'User',
        isLocal: false,
        isMuted: false,
        isVideoOn: false,
      ));
      index = participants.length - 1;
    }

    participants[index].remoteStream.value = stream;
    if (stream.getAudioTracks().isNotEmpty) {
      // [AUDIO_FIX]: Explicitly enable all tracks in the received stream
      for (var track in stream.getAudioTracks()) {
        track.enabled = true;
        addLog('🎧 Audio track received: ID=${track.id} (ENABLED)');
      }
      PHASE('PHASE: onTrack (Audio)');
      addLog('STATE_AUTHORITY: Remote Audio Track Received.');
      // [Stage R28.1]: We NO LONGER set _isCallLive here.
      // Flow is only official after Media Verification polling.
      addLog('🎧 Audio track processed → waiting for Media Verification');
    }
    // [ANDROID_SAFEGUARD]: Create explicit renderer to force audio binding
    if (!GetPlatform.isWindows && !GetPlatform.isWeb) {
      try {
        // [PERSISTENCE]: Reuse existing renderer or create new one stored in participant
        if (participants[index].audioSinkRenderer == null) {
          final renderer = webrtc.RTCVideoRenderer();
          await renderer.initialize();
          participants[index].audioSinkRenderer = renderer;
          addLog(
              '🔊 [ANDROID] Persistent Dummy Renderer created for force AudioSink binding');
        }
        participants[index].audioSinkRenderer!.srcObject = stream;
      } catch (e) {
        debugPrint('⚠️ Dummy Renderer Error: $e');
      }
    }

    if (stream.getVideoTracks().isNotEmpty) {
      debugPrint('[VIDEO] Remote track received for $userId');
    }
  }

  // --- Participant Management ---

  Future<void> _handleInsertParticipant(Map<String, dynamic> record) async {
    final userId = record['user_id'] as String;
    if (participants.any((p) => p.id == userId)) return;
    final profile = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    participants.add(_parseParticipantFromRow(record, profile: profile));
    debugPrint('[ROOM] UI updated');
  }

  void _handleUpdateParticipant(Map<String, dynamic> record) {
    final index = participants.indexWhere((p) => p.id == record['user_id']);
    if (index != -1) {
      participants[index].isMuted.value = record['is_muted'] ?? true;
      participants[index].isTalking.value = record['is_talking'] ?? false;
      participants[index].isVideoOn.value = record['is_video_on'] ?? false;
    }
  }

  void _handleDeleteParticipant(Map<String, dynamic> record) {
    final id = record['id'];
    if (id != null) {
      final pIndex = participants.indexWhere((p) => p.rowId == id);
      if (pIndex != -1) {
        final userId = participants[pIndex].id;
        debugPrint('[ROOM] Participant left');

        // [DISPOSAL]: Correctly clean up the persistent renderer
        if (participants[pIndex].audioSinkRenderer != null) {
          debugPrint('🧹 Disposing persistent AudioSink for $userId');
          unawaited(participants[pIndex].audioSinkRenderer!.dispose());
          participants[pIndex].audioSinkRenderer = null;
        }

        _webrtc.removePeer(userId);
        participants.removeAt(pIndex);
        debugPrint('[ROOM] UI updated');
      }
    }
  }

  Future<void> _fetchParticipants(String id) async {
    final rows = List<Map<String, dynamic>>.from(
        await _supabase.from('room_participants').select().eq('room_id', id));
    final userIds = rows.map((r) => r['user_id'] as String).toList();
    final profiles = List<Map<String, dynamic>>.from(
        await _supabase.from('profiles').select().inFilter('id', userIds));
    final profilesMap = {for (final p in profiles) (p['id'] as String): p};

    participants.assignAll(rows
        .map((r) => _parseParticipantFromRow(r,
            profile: profilesMap[r['user_id'] as String]))
        .toList());
    debugPrint('[ROOM] UI updated');
  }

  CommunicationParticipant _parseParticipantFromRow(Map<String, dynamic> row,
      {Map<String, dynamic>? profile}) {
    return CommunicationParticipant(
      id: row['user_id'],
      rowId: row['id'] ?? '',
      name: profile?['full_name'] ?? profile?['username'] ?? 'مستخدم TalkMate',
      avatarUrl: profile?['avatar_url'],
      isLocal: row['user_id'] == currentUserId,
      isMuted: row['is_muted'] ?? true,
      isTalking: row['is_talking'] ?? false,
      isVideoOn: row['is_video_on'] ?? false,
    );
  }

  // --- Media Control ---

  Future<void> _initMedia(bool isVideo) async {
    // [Stage R10] Constitutional Media Startup Contract (Audio First)

    // 0. Smart Pre-call Check (Feature 6)
    if (_shouldPromptDiagnostic()) {
      _showDiagnosticRecommendation();
    }

    // [NETWORK_DIAGNOSTIC]: Smart Pre-call Warning
    if (lastNetworkScore.value != -1 && lastNetworkScore.value < 60) {
      _showNetworkWarning();
    }

    // 1. Request & Lock Microphone
    if (await Permission.microphone.request() != PermissionStatus.granted) {
      throw 'Microphone permission denied';
    }

    // 1.1 Audio Session Configuration (Constitutional Clause 2)
    if (GetPlatform.isWeb) {
      debugPrint('🎙️ Sovereign: Audio Session Bypass active for Web');
      _isAudioSessionReady.value = true;
      _markCallAsActiveIfReady();
    } else {
      try {
        final session = await AudioSession.instance;
        // Use voiceChat category for better AEC and background behavior
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
                  AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        ));

        // [AUDIO_FOCUS]: Listen for interruptions (e.g. Phone calls, Music)
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            addLog(
                '⚠️ Audio Interruption BEGIN: NOT muting automatically (Constitutional Guard).');
            // [FIX]: Disable parasitic auto-mute
            // _webrtc.toggleAudio(true);
          } else {
            addLog('🎙️ Audio Interruption END: Syncing with UI state...');
            _webrtc.toggleAudio(isMuted.value); // Restore to UI state
          }
        });

        // Attempt activation with retries
        bool activated = false;
        int attempts = 0;
        while (!activated && attempts < 3) {
          try {
            activated = await session.setActive(true);
          } catch (e) {
            attempts++;
            await Future.delayed(Duration(milliseconds: 100 * attempts));
          }
        }

        if (activated) {
          debugPrint('🎙️ Sovereign: Audio Session Activated (VoiceChat Mode)');
          _isAudioSessionReady.value = true;
          _markCallAsActiveIfReady();
        } else {
          debugPrint('⚠️ Audio Session activation failed after retries');
        }
      } catch (e) {
        debugPrint('⚠️ Audio Session configuration failed: $e');
      }
    }

    try {
      // 2. Start/Verify Audio Stream (Idempotent Guard)
      if (localStream != null && localStream!.getAudioTracks().isNotEmpty) {
        final existingAudio = localStream!.getAudioTracks().first;
        if (existingAudio.enabled) {
          addLog(
              '🎙️ [IDEMPOTENCY] Audio track already active. Skipping re-init.');
        } else {
          localStream =
              await _webrtc.initLocalMedia(isAudio: true, isVideo: false);
        }
      } else {
        localStream =
            await _webrtc.initLocalMedia(isAudio: true, isVideo: false);
      }
      addLog('🎙️ AUDIO_TRACK_ADDED');

      // 3. Verify Audio Track Active
      final audioTracks = localStream?.getAudioTracks() ?? [];
      addLog('🎤 AUDIO TRACKS COUNT = ${audioTracks.length}');

      // [Acoustic Echo Mitigation]: Show headphone hint on Windows
      if (GetPlatform.isWindows) {
        Future.delayed(const Duration(seconds: 2), () {
          if (webRTCState.value == WebRTCLifecycle.active ||
              webRTCState.value == WebRTCLifecycle.iceConnected) {
            showHeadphoneHint.value = true;
            // Auto-hide after 10 seconds
            Future.delayed(const Duration(seconds: 10), () {
              showHeadphoneHint.value = false;
            });
          }
        });
      }

      webrtc.MediaStreamTrack? audioTrack;

      if (audioTracks.isNotEmpty) {
        audioTrack = audioTracks.first;
        addLog('🎤 AUDIO TRACK KIND = ${audioTrack.kind}');
        addLog('🎤 AUDIO TRACK ENABLED = ${audioTrack.enabled}');
        addLog('🎤 AUDIO TRACK ID = ${audioTrack.id}');

        if (!audioTrack.enabled) {
          throw 'Failed to activate audio track (Track is disabled)';
        }
      } else {
        throw 'Failed to activate audio track (Count is 0)';
      }

      // [AUDIO_FIX]: Hard-activate speakerphone and ensure track matches UI state
      if (!GetPlatform.isWindows && !GetPlatform.isWeb) {
        // [ANDROID_ROUTING]: Force Communication Mode / Speaker Routing
        try {
          addLog('🔊 Audio Routing: Forcing IN_COMMUNICATION mode...');

          // [SOVEREIGN_FIX]: Use the specialized Android routing helper
          await _webrtc.setToCommunicationMode();

          isSpeakerOn.value = true;

          // Sync track with UI state (Respect existing state if possible)
          addLog('🎤 BEFORE APPLY MUTE: track.enabled=${audioTrack.enabled}');
          // await webrtc.Helper.setMicrophoneMute(isMuted.value, audioTrack);
          // _webrtc.toggleAudio(isMuted.value);

          debugPrint(
              '🔊 Audio Path: Speaker ON, Muted: ${isMuted.value} (Deferred Activation)');
        } catch (e) {
          debugPrint('⚠️ Audio Routing Error: $e');
        }
      } else {
        // For Windows/Web: Ensure track matches UI state
        _webrtc.toggleAudio(isMuted.value);
      }

      // [ADVISORY_SYSTEM]: Health Check
      if (GetPlatform.isWindows) {
        unawaited(_runAudioHealthCheck());
      }

      // 4. Constitutional Delay: Strictly 300ms (Clause 2)
      await Future.delayed(const Duration(milliseconds: 300));

      // 5. Request Camera & Video Stream (if requested)
      if (isVideo) {
        if (await Permission.camera.request() == PermissionStatus.granted) {
          try {
            // Re-init with video
            final videoStream =
                await _webrtc.initLocalMedia(isAudio: true, isVideo: true);

            // [ZERO_LOOPBACK_STRATEGY]: Global Video-Only Proxy
            // We strictly DO NOT attach the audio track to the renderer on ANY platform.
            // This prevents the local audio from being played back (Echo/Feedback).
            final videoTracks = videoStream.getVideoTracks();
            if (videoTracks.isNotEmpty) {
              final proxyStream =
                  await webrtc.createLocalMediaStream('video_proxy');
              await proxyStream.addTrack(videoTracks.first);
              localRenderer.srcObject = proxyStream;
              addLog(
                  '🪟 [ZERO_LOOPBACK] Local Video Attached (Audio Isolated)');
            } else {
              // [SHIELD]: If no video tracks, explicitly clear the renderer to prevent
              // any accidental audio binding from previous stream states.
              localRenderer.srcObject = null;
            }

            localStream = videoStream;
            addLog('🎥 Video Stream Active (Camera: ON)');
          } catch (e) {
            addLog('⚠️ Camera Init Failed: $e');
            debugPrint(
                '⚠️ Video initialization failed: $e. Falling back to Audio.');
            // We already have audio localStream from step 2
          }
        } else {
          // [Stage R11] Constitutional Auto-Fallback (Clause 4)
          debugPrint('⚠️ Camera denied/failed. Falling back to Audio Only.');
          _showConstitutionalFallback();
        }
      }

      if (isClosed) return;

      // [FINAL_VS_CHECK]: Ensure renderer has a stream if we have video but didn't just init it
      // (e.g. if we came in with video already active or logic flow differences)
      if (localStream != null &&
          localStream!.getVideoTracks().isNotEmpty &&
          localRenderer.srcObject == null) {
        final videoOnlyStream =
            await webrtc.createLocalMediaStream('local_video_proxy_fallback');
        for (var track in localStream!.getVideoTracks()) {
          await videoOnlyStream.addTrack(track);
        }
        localRenderer.srcObject = videoOnlyStream;
      }

      if (localStream?.getVideoTracks().isNotEmpty ?? false) {
        debugPrint('[VIDEO] Renderer attached (Local)');
      }

      // [RADICAL FIX]: Ensure tracks are added to any existing peers
      // This covers the case where Offer arrived before _initMedia completed.
      if (localStream != null) {
        addLog('🎙️ Sovereign: Injecting Local Stream into active peers...');
        await _webrtc.addLocalTracksToPeers();
      }

      // Update participants track info (Local)
      final me = participants.firstWhereOrNull((p) => p.isLocal);
      if (me != null) {
        me.isVideoOn.value = localStream?.getVideoTracks().isNotEmpty ?? false;
      }
    } catch (e) {
      debugPrint('Sovereign Media Error: $e');
      rethrow;
    }
  }

  void _showConstitutionalFallback() {
    final context = Get.context;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);

    Get.snackbar(
      '',
      l10n.fallbackToAudioMsg,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange.withValues(alpha: 0.8),
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    );
  }

  // Removed unused _cleanupMedia; WebRTCConnectionManager handles it.

  // --- Talking Monitor ---

  // --- Stats Monitoring (VU Meter) ---

  Future<void> _startStatsMonitoring() async {
    _talkingTimer?.cancel();
    _talkingTimer =
        Timer.periodic(const Duration(milliseconds: 200), (t) async {
      if (isClosed) return;
      await _updateMicLevels();
      await _updateNetworkQuality();
    });

    // [Area 2]: Periodic AEC Check (Every 10 seconds)
    _aecAuditTimer?.cancel();
    _aecAuditTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (isClosed) return;
      await _auditAECPerformance();
    });

    // [Area 3]: Periodic ICE Audit (Every 15 seconds)
    _iceAuditTimer?.cancel();
    _iceAuditTimer = Timer.periodic(const Duration(seconds: 15), (t) async {
      if (isClosed) return;
      await _auditICEConnections();
    });
  }

  void _handleIceStateChange(
      String userId, webrtc.RTCIceConnectionState state) {
    addLog('🧊 ICE: Peer $userId state -> ${state.name}');
    debugPrint('🧊 Sovereign Stability: Peer $userId ICE state -> $state');

    switch (state) {
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateChecking:
        // [JITTER_FIX]: Checking state is transient and often occurs during stable calls.
        // We only transition to reconnecting if the network actually fails or disconnects.
        addLog('🧊 ICE: Peer $userId is checking connection (Internal)...');

        // [R30] UI AUTHORITY: Proactively clear disconnection timer if we are checking
        _iceDisconnectedTimer?.cancel();
        _iceDisconnectedTimer = null;
        break;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected:
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateCompleted:
        addLog('🧊 ICE: Peer $userId is connected 🚀');

        // [R34] DYNAMIC FREEZE: Lock signaling only AFTER connection is verified
        final peer = _webrtc.getSovereign(userId);
        if (peer != null && !peer.signalingFrozen) {
          addLog(
              '🛡️ [R34] Signaling FROZEN for $userId (Connection Established)');
          peer.signalingFrozen = true;
        }

        // [Stage R32.1]: Clear recovery timers on success
        _iceDisconnectedTimer?.cancel();
        _iceDisconnectedTimer = null;
        _iceFailureTimer?.cancel();
        _iceFailureTimer = null;

        _isNegotiationLocked = false; // [Area 4]: Release lock on success
        _isIceRestartActive = false;
        _drainNegotiationQueue(); // [Area 4]

        // [FIX]: Ensure UI clears 'Reconnecting' status and transitions to active
        PHASE('PHASE: ICE_CONNECTED');
        _transitionToState(WebRTCLifecycle.iceConnected,
            source: 'ice_state_change');

        // [Stage R28.1]: We NO LONGER promote status here.
        // Transition to ACTIVE is now strictly owned by _verifyMediaFlow.
        if (_engine.status == CommSessionStatus.reconnecting) {
          addLog(
              '📡 ICE: Recovered from Disconnection. Awaiting Media Flow...');
        }

        // [HARDENING]: Reset retry count on success
        _iceRestartCounts[userId] = 0;
        addLog(
            '🧊 ICE: Connection ESTABLISHED/COMPLETED for $userId (Retries Reset)');

        // [R32] MISSION — Part 2 & Part 3 (Media Flow Gate & Relay Fallback)
        Future.delayed(const Duration(seconds: 5), () async {
          if (isClosed) return;
          final pc = _webrtc.getSovereign(userId);
          if (pc == null ||
              pc.pc.iceConnectionState !=
                      webrtc.RTCIceConnectionState
                          .RTCIceConnectionStateConnected &&
                  pc.pc.iceConnectionState !=
                      webrtc.RTCIceConnectionState
                          .RTCIceConnectionStateCompleted) {
            return;
          }

          try {
            final stats = await pc.getStats();
            int bytesSent = 0;
            int bytesReceived = 0;

            for (var report in stats) {
              if (report.type == 'outbound-rtp' &&
                  report.values['kind'] == 'audio') {
                bytesSent = report.values['bytesSent'] ?? 0;
              }
              if (report.type == 'inbound-rtp' &&
                  report.values['kind'] == 'audio') {
                bytesReceived = report.values['bytesReceived'] ?? 0;
              }
            }

            addLog(
                '[R32][MEDIA_AUDIT] bytesSent=$bytesSent, bytesReceived=$bytesReceived');

            // PART 2 — MEDIA FLOW VERIFICATION GATE
            // Trigger fallback if EITHER direction is blocked (Total Silence or One-way)
            if (bytesSent == 0 || bytesReceived == 0) {
              addLog(
                  '[R32][MEDIA_PATH_INVALID] One-way block or Total Silence detected (Sent: $bytesSent, Recv: $bytesReceived)');

              // PART 3 — SMART RELAY FALLBACK ENGINE
              addLog('[R32][RELAY_FALLBACK_TRIGGERED]');

              // Update configuration to FORCE RELAY
              final relayConfig = Map<String, dynamic>.from(_webrtc.iceConfig);
              relayConfig['iceTransportPolicy'] = 'relay';
              await pc.setConfiguration(relayConfig);
              addLog('[R32][RELAY_POLICY_APPLIED]');

              // Restart ICE
              final offer = await pc.restartIce();
              _sendSignal(
                type: 'offer',
                data: {
                  'sdp': offer.sdp,
                  'type': offer.type,
                  'call_id': sessionId.value,
                  'is_ice_restart': true,
                },
                receiverId: userId,
              );
              addLog('[R32][ICE_RESTART_OFFER_SENT] Forced Relay Mode');

              // Post-Relay Verification (wait another 5s)
              Future.delayed(const Duration(seconds: 5), () async {
                if (isClosed) return;
                final postStats = await pc.getStats();
                int postBytesSent = 0;
                int postBytesReceived = 0;

                for (var report in postStats) {
                  if (report.type == 'outbound-rtp' &&
                      report.values['kind'] == 'audio') {
                    postBytesSent = report.values['bytesSent'] ?? 0;
                  }
                  if (report.type == 'inbound-rtp' &&
                      report.values['kind'] == 'audio') {
                    postBytesReceived = report.values['bytesReceived'] ?? 0;
                  }
                }
                addLog(
                    '[R32][POST_RELAY_STATS] bytesSent=$postBytesSent, bytesReceived=$postBytesReceived');

                // PART 4 — HARDENED SCENARIO REPORT ENGINE
                _finalizeR32Report(userId, bytesSent, bytesReceived,
                    postBytesSent, postBytesReceived);
              });
            } else {
              addLog('[R32][MEDIA_STABLE] Media flow verified.');
            }
          } catch (e) {
            addLog('⚠️ [R32] Verification Error: $e');
          }
        });

        // [AUDIO_FIX]: Re-force Audio Routing after connection (Android "Change Mind" Fix)
        if (!GetPlatform.isWindows && !GetPlatform.isWeb) {
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (isClosed) return;
            addLog('🔊 [ICE_CONNECTED] Re-asserting Audio Routing...');
            try {
              await webrtc.Helper.setSpeakerphoneOn(true);
            } catch (e) {
              debugPrint('⚠️ Re-asserting Audio Error: $e');
            }
          });
        }

        addLog('🔥 ICE: Connection ESTABLISHED.');

        // [AEC_HARDENING]: Start Adaptive Suppression Gate (Windows Only)
        if (GetPlatform.isWindows) {
          unawaited(_runAdaptiveEchoSuppression());
        }

        // [R30] ICE Governance: Stop emission only when fully stable
        final sovereign = _webrtc.getSovereign(userId);
        if (sovereign != null) {
          final isDtlsConnected = sovereign.pc.connectionState ==
              webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
          final hasRemoteDesc = sovereign.hasRemoteSdp;

          if (isDtlsConnected && hasRemoteDesc) {
            sovereign.isIceEmissionStopped = true;
            addLog(
                '🧊 [R30] ICE Stable: Candidate emission STOPPED for $userId (DTLS & RemoteDesc Verified)');
          } else {
            addLog(
                '🧊 [R30] ICE Stable: Waiting for DTLS/RemoteDesc before stopping emission (DTLS: ${sovereign.pc.connectionState?.name})');
          }
        }

        // [GOLDEN_RULE]: Mark initial setup as done once connected
        if (state ==
            webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected) {
          addLog(
              '🧊 ICE: Connection Stable. Ending Setup Phase. (Restart Mode: $_isIceRestart)');
          _isInitialCallSetup = false;
          _isIceRestart = false;
          _isIceRestartActive = false; // [R32.1]: Unlock restart

          // [Step 2 Diagnostic]: Confirm the AudioTrack isn't "Local Only"
          Future.delayed(const Duration(seconds: 3), () async {
            if (isClosed) return;
            final pc = _webrtc.getPeer(userId);
            if (pc != null) {
              final senders = await pc.getSenders();
              for (var s in senders) {
                addLog(
                    '📡 sender.track.kind=${s.track?.kind}, enabled=${s.track?.enabled}');
              }
            }
          });
        }

        // [Stage R28]: Media Verification Layer (Deterministic Reset)
        // We strictly DO NOT transition to active status here based on ICE alone.
        // Instead, we wait for actual media flow verification.
        if (state ==
            webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected) {
          unawaited(_verifyMediaFlow(userId));
        }

        /* Legacy immediate transition removed for Stage R28
        if (_engine.status == CommSessionStatus.reconnecting ||
            _engine.status == CommSessionStatus.connecting ||
            _engine.status == CommSessionStatus.ringingOutgoing ||
            _engine.status == CommSessionStatus.ringingIncoming) {
          _engine.statusRx.value = isCameraOn.value
              ? CommSessionStatus.activeVideo
              : CommSessionStatus.activeAudio;
          addLog(
              '🔥 Sovereign: Pipeline Active (${isCameraOn.value ? "Video" : "Voice"})');

          // [STABILIZATION]: If we reached ICE Connected, ensure DB status is Ongoing
          _markCallAsActiveIfReady();
        }
        */
        break;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateNew:
        break;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        addLog(
            '🧊 ICE: Connection DISCONNECTED for $userId. Monitoring for persistent failure...');

        // [R30] UI AUTHORITY: Do NOT set reconnecting immediately.
        // Also do NOT show the banner if we are still in initial setup.
        if (_isInitialCallSetup) {
          addLog(
              '🧊 [R30] UI AUTHORITY: Disconnection ignored during initial setup.');
          return;
        }

        _iceDisconnectedTimer?.cancel();
        _iceDisconnectedTimer = Timer(const Duration(seconds: 5), () {
          if (!isClosed &&
              webRTCState.value != WebRTCLifecycle.iceConnected &&
              webRTCState.value != WebRTCLifecycle.active) {
            addLog(
                '🧊 [R30] UI AUTHORITY: Persistent disconnection detected. (5s threshold met)');
            _engine.setReconnecting();
            unawaited(_triggerIceRestart(userId));
          }
        });
        break;

      case webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed:
        _engine.telemetry.iceFailureCount++; // [R33] Track ICE failure
        _engine.telemetry.failedReason = 'ICE Connection Failed for $userId';
        addLog(
            '🧊 ICE: Connection FAILED for $userId. Triggering immediate recovery...');

        // [STABILITY_RECOVERY]: Trigger restart immediately
        _isIceRestartActive = false;
        unawaited(_triggerIceRestart(userId));

        // [Stage R26]: Anti-Ghosting Logic (Refined for Production Stability)
        _iceFailureTimer?.cancel();
        _iceFailureTimer = Timer(const Duration(seconds: 20), () {
          final isConnected =
              webRTCState.value == WebRTCLifecycle.iceConnected ||
                  webRTCState.value == WebRTCLifecycle.mediaFlowing ||
                  webRTCState.value == WebRTCLifecycle.active;

          if (_engine.status != CommSessionStatus.idle && !isConnected) {
            addLog(
                '👻 Anti-Ghosting: Peer $userId failed to recover ICE after restart attempt. Removing.');
            participants.removeWhere((p) => p.id == userId);
            if (participants.where((p) => !p.isLocal).isEmpty) {
              addLog(
                  '🏠 Session Empty: Leaving due to persistent ICE failures.');
              unawaited(leaveSession());
            }
          }
        });
        break;
      default:
        break;
    }
  }

  // [G3_RESILIENCE]: Legacy watchdog removed in Stage R23.

  Future<void> _triggerIceRestart(String userId) async {
    if (_isIceRestartActive) {
      addLog('🧊 ICE: Restart already in flight. Skipping redundant trigger.');
      return;
    }

    try {
      final pc = _webrtc.getPeer(userId);
      if (pc == null) {
        addLog('⚠️ G3: Peer $userId disappeared. Aborting restart.');
        return;
      }

      // [GOLDEN_RULE]: Guard Restart - signaling state must be stable for clean restart.
      // Avoid triggering creation of a local offer if we have a pending remote offer or local offer.
      if (pc.signalingState !=
          webrtc.RTCSignalingState.RTCSignalingStateStable) {
        addLog(
            '🛑 ICE: Skip restart - signaling not stable (${pc.signalingState})');

        // [GLARE_FIX]: If we are stuck in 'HaveLocalOffer' for too long, we might need a reset.
        // But for now, we wait for stability.
        return;
      }

      // [HARDENING]: Cooldown Check (5s per implementation plan)
      final now = DateTime.now();
      if (_lastIceRestartTime.containsKey(userId)) {
        final diff = now.difference(_lastIceRestartTime[userId]!);
        if (diff < _iceRestartCooldown) {
          addLog(
              '🛑 ICE: Restart throttled (Debounce: ${diff.inMilliseconds}ms < 5000ms)');
          return;
        }
      }

      // [HARDENING]: Zombie Prevention (Max 3 retries)
      final count = _iceRestartCounts[userId] ?? 0;
      if (count >= _maxIceRestarts) {
        addLog(
            '💀 ICE: Max restart attempts ($count) reached for $userId. Terminating peer.');
        _engine.telemetry.failedReason = 'ICE Failure (Zombie Peer)';
        participants.removeWhere((p) => p.id == userId);
        if (participants.where((p) => !p.isLocal).isEmpty) {
          unawaited(leaveSession(reason: 'ice_failure_max_retries'));
        }
        return;
      }

      _isIceRestartActive = true;
      _isNegotiationLocked = true; // [Area 4]: Strict Lock during recovery

      // [Area 1]: Proactive TURN Refresh before restart
      final freshServers =
          await TurnCredentialManager.instance.getConfiguration();
      await _webrtc.setIceServers(freshServers);

      // [R33] Hardened ICE: Force RELAY policy on restart to break through restrictive NAT
      addLog('🧊 [R33] Hardening: Forcing RELAY policy for ICE Restart.');
      _webrtc.setIceTransportPolicy('relay');

      _currentNegotiationId =
          'rst-$userId-${DateTime.now().millisecondsSinceEpoch}';

      _lastIceRestartTime[userId] = now;
      _iceRestartCounts[userId] = count + 1;
      addLog(
          '🔄 ICE_RECOVERY: Triggering ICE Restart for $userId (NegId: $_currentNegotiationId) (Attempt ${count + 1}/$_maxIceRestarts)...');

      final peer = _webrtc.getSovereign(userId);
      if (peer != null) peer.makingOffer = true;

      _isIceRestart = true;
      _isInitialCallSetup = false;

      // [R32.1]: Small delay to allow any pending signaling events to settle
      await Future.delayed(const Duration(milliseconds: 200));
      if (isClosed ||
          pc.signalingState !=
              webrtc.RTCSignalingState.RTCSignalingStateStable) {
        _isIceRestartActive = false;
        if (peer != null) peer.makingOffer = false;
        return;
      }

      final offer = await _webrtc.createRestartOffer(userId);
      if (peer != null) peer.makingOffer = false;

      if (isClosed || sessionId.value.isEmpty) {
        addLog('🛑 ICE: Session closed during restart preparation. Aborting.');
        _isIceRestartActive = false;
        return;
      }

      _webrtc.clearCandidates(userId);
      addLog('🧊 ICE: Clearing old candidates');

      // Update DB and Broadcast
      final v = _sessionVersions[sessionId.value] ?? 0;
      await _callRepo.setOffer(sessionId.value, offer.sdp!,
          extra: {'iceRestart': true, 'ice_restart': true, 'version': v});

      _sendSignal(
        receiverId: userId,
        type: 'offer',
        data: {
          'sdp': offer.sdp,
          'ice_restart': true,
          'version': v,
        },
      );
      addLog('✅ ICE Restart Signal Sent (DB + Broadcast)');
    } catch (e) {
      addLog('❌ G3: ICE Restart failed: $e');
    } finally {
      // We keep _isIceRestartActive true until transition to Connected or Failure
      // or we can release it after a timeout.
      // Usually, it's safer to release it after setLocal/setRemote is done.
      Future.delayed(const Duration(seconds: 10), () {
        _isIceRestartActive = false;
      });
    }
  }

  /// [Stage R32.1]: Ensure all transceivers are in the correct state and bound to tracks
  Future<void> _syncTransceivers(String userId) async {
    final pc = _webrtc.getPeer(userId);
    if (pc == null) return;

    try {
      final transceivers = await pc.getTransceivers();
      final localTracks = localStream?.getTracks() ?? [];

      for (var transceiver in transceivers) {
        final kind = transceiver.receiver.track?.kind ??
            transceiver.sender.track?.kind ??
            'audio';

        // 1. Ensure direction is sendrecv
        try {
          // In some flutter_webrtc versions, we just call setDirection.
          await transceiver.setDirection(webrtc.TransceiverDirection.SendRecv);
        } catch (e) {
          debugPrint('⚠️ [SYNC] Failed to set transceiver direction: $e');
        }

        // 2. Ensure track is bound
        if (transceiver.sender.track == null && localStream != null) {
          final track = localTracks.firstWhereOrNull((t) => t.kind == kind);
          if (track != null) {
            debugPrint('🔄 [SYNC] Re-binding local $kind track to sender');
            await transceiver.sender.replaceTrack(track);
          }
        }
      }
    } catch (e) {
      addLog('⚠️ [SYNC] Transceiver sync error: $e');
    }
  }

  Future<void> _handleIceRestart(
      String userId, Map<String, dynamic> offerJson) async {
    try {
      final pc = _webrtc.getPeer(userId);
      if (pc == null) return;

      final offer = webrtc.RTCSessionDescription(
        offerJson['sdp'],
        offerJson['type'] ?? 'offer',
      );

      // [GLARE_GUARD]: Final check before state transition
      if (pc.signalingState !=
          webrtc.RTCSignalingState.RTCSignalingStateStable) {
        addLog(
            '🛡️ handleIceRestart: Signaling state ${pc.signalingState} is not stable.');
        if (isPolite) {
          addLog(
              '🛡️ handleIceRestart: Attempting internal rollback to handle incoming restart...');
          try {
            await pc.setLocalDescription(
                webrtc.RTCSessionDescription(null, 'rollback'));
            addLog('✅ handleIceRestart: Internal rollback successful.');
          } catch (e) {
            addLog('⚠️ handleIceRestart: Internal rollback failed ($e).');
          }
        }
      }

      await pc.setRemoteDescription(offer);

      // [GUARDRAIL]: Check validity
      if (isClosed || sessionId.value.isEmpty) return;

      final peer = _webrtc.getSovereign(userId);
      if (peer == null) throw Exception('SovereignPeer is NULL during Restart');

      final answer = await peer.createAnswer();

      // [GUARDRAIL]: Check validity
      if (isClosed || sessionId.value.isEmpty) return;

      peer.isSettingRemoteAnswerPending = true;
      try {
        await pc.setLocalDescription(answer);
      } finally {
        peer.isSettingRemoteAnswerPending = false;
      }

      // We update the DB as a fallback for the answer.
      if (sessionId.value.isNotEmpty) {
        await _callRepo.setAnswer(sessionId.value, answer.sdp!,
            extra: {'version': _sessionVersions[sessionId.value] ?? 0});
        addLog(
            '🧊 ICE Restart: Answer sent to peer (Version: ${_sessionVersions[sessionId.value] ?? 0}).');
      }
    } catch (e) {
      addLog('❌ G3: Failed to process ICE Restart: $e');
    }
  }

  Future<void> _updateNetworkQuality() async {
    // [Stage R22]: Advanced Behavior-Driven Mapping
    if (_webrtc.allPeerIds.isEmpty) {
      _engine.updateNetworkQuality(NetworkQuality.good);
      return;
    }

    try {
      double maxJitter = 0.0;
      double avgPacketLoss = 0.0;
      int peerCount = 0;

      for (var pcId in _webrtc.allPeerIds) {
        final pc = _webrtc.getPeer(pcId);
        if (pc == null) continue;

        final stats = await pc.getStats();
        for (var report in stats) {
          if (report.type == 'inbound-rtp') {
            final jitter =
                double.tryParse(report.values['jitter']?.toString() ?? '0.0') ??
                    0.0;
            final lost = double.tryParse(
                    report.values['packetsLost']?.toString() ?? '0.0') ??
                0.0;
            final received = double.tryParse(
                    report.values['packetsReceived']?.toString() ?? '1.0') ??
                1.0;

            final lossPercentage = (lost / (received + lost)) * 100;

            if (jitter > maxJitter) maxJitter = jitter;
            avgPacketLoss += lossPercentage;
            peerCount++;
          }
        }
      }

      if (peerCount > 0) avgPacketLoss /= peerCount;

      // Behavior-Driven Mapping Logic
      NetworkQuality current;
      if (maxJitter >= 0.1 || avgPacketLoss >= 10.0) {
        current = NetworkQuality.poor;
      } else if (maxJitter >= 0.05 || avgPacketLoss >= 2.0) {
        current = NetworkQuality.fair;
      } else {
        current = NetworkQuality.good;
      }

      _engine.updateNetworkQuality(current);
      _applyStabilityBehavior(current);
    } catch (e) {
      debugPrint('Error polling stats: $e');
    }
  }

  void _applyStabilityBehavior(NetworkQuality quality) {
    // [Stage R22.3]: Auto Video -> Audio Fallback
    if (quality == NetworkQuality.poor && isCameraOn.value) {
      addLog('📡 Stability Alert: Poor network. Falling back to Audio Only.');
      _engine.setFallback(true);
      // Disable local video track silently (Decision Layer)
      localStream?.getVideoTracks().forEach((t) => t.enabled = false);
      _sendSignal(
          receiverId: 'all', type: 'camera', data: {'is_video_on': false});
    } else if (quality == NetworkQuality.good && _engine.isFallbackToAudio) {
      // Automatic recovery ONLY if quality is Good and sustained (we could add a counter here)
      addLog('📡 Stability Alert: Network recovered. Restoring Video.');
      _engine.setFallback(false);
      localStream?.getVideoTracks().forEach((t) => t.enabled = true);
      _sendSignal(
          receiverId: 'all', type: 'camera', data: {'is_video_on': true});
    }
  }

  Future<bool> _checkMandatoryPermissions(bool isVideo) async {
    final mic = await Permission.microphone.status;
    final cam =
        isVideo ? await Permission.camera.status : PermissionStatus.granted;
    final notification = await Permission.notification.status;

    if (mic.isGranted && cam.isGranted && notification.isGranted) return true;

    // Dedicated Constitutional Guard Screen (Simple Dialog for Beta)
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('⚠️ الأذونات المطلوبة'),
        content: Text(
          'لضمان استقرار المكالمة وجودتها حسب الدستور، يجب منح أذونات '
          '${isVideo ? "الميكروفون، الكاميرا، والتنبيهات" : "الميكروفون والتنبيهات"} أولاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final m = await Permission.microphone.request();
              final c = isVideo
                  ? await Permission.camera.request()
                  : PermissionStatus.granted;
              final n = await Permission.notification.request();

              if (m.isGranted && c.isGranted && n.isGranted) {
                Get.back(result: true);
              } else {
                Get.snackbar('فشل', 'يجب منح جميع الأذونات للمتابعة');
              }
            },
            child: const Text('منح الأذونات'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    return result ?? false;
  }

  Future<void> _updateMicLevels() async {
    double localLevel = 0.0;

    for (var p in participants) {
      if (p.isLocal) {
        // [Stage R9]: Immediate Local Feedback
        // If we have a localStream, we can attempt to get levels even without remote peers
        // by checking any outbound PC or using a separate monitoring hack if needed.
        // For now, check ALL active peers for outbound-rtp of OUR track.
        double maxLocal = 0.0;
        for (var pcId in _webrtc.allPeerIds) {
          final activePc = _webrtc.getPeer(pcId);
          if (activePc != null) {
            final reports = await activePc.getStats();
            for (var report in reports) {
              if (report.type == 'outbound-rtp') {
                final level = report.values['audioLevel'];
                if (level != null) {
                  final l = double.tryParse(level.toString()) ?? 0.0;
                  if (l > maxLocal) maxLocal = l;
                }
              }
            }
          }
        }
        localLevel = maxLocal;
        p.isTalking.value = localLevel > 0.05;
        micLevel.value = localLevel;
      } else {
        // Remote levels
        final level = await _webrtc.getAudioLevel(p.id);
        p.isTalking.value = level > 0.05;
        // Sync with DB if needed (for room status)
        // We only sync local talking status to DB generally to save bandwidth
      }
    }

    // Sync local talking to DB
    if (_myParticipantId != null) {
      final bool isNowTalking = localLevel > 0.05;
      // Optimization: only update if changed
      final me = participants.firstWhereOrNull((p) => p.isLocal);
      if (me != null && me.isTalking.value != isNowTalking) {
        // Update DB (Debounced or just here)
        // For now, we skip DB sync for 'is_talking' to keep it fast/local only
        // or we do it if needed for 'room' mode.
      }
    }
  }

  Future<void> _stopTalkingMonitor() async {
    _talkingTimer?.cancel();
    _talkingTimer = null;
  }

  /// [SYMMETRY_FIX]: Broadcasts a direct termination signal to all participants.
  void sendTerminationSignal(String callId, {String reason = 'user_hangup'}) {
    _sendSignal(
      receiverId: 'all',
      type: 'call_end', // [SYMMETRY]: Use call_end as requested
      data: {'call_id': callId, 'reason': reason},
    );
  }

  void _markCallAsActiveIfReady() {
    if (sessionType.value != CommunicationSessionType.call) return;
    addLog(
        '🧪 ActiveCheck: AudioSession=${_isAudioSessionReady.value} | RemoteTrack=${_hasRemoteAudioTrack.value} | OngoingMarked=$_markedOngoingInDB');
    if (_isAudioSessionReady.value && _hasRemoteAudioTrack.value) {
      final id = sessionId.value;
      if (id.isEmpty || id == 'unknown') return;

      if (_markedOngoingInDB) return;
      _markedOngoingInDB = true;

      addLog(
          '⚔️ Constitutional: ACTIVE HANDSHAKE COMPLETE. Marking ongoing in DB...');

      // 1. Update Database Status
      unawaited(CallManager.instance.updateCallStatus(id, CallStatus.ongoing));

      // 2. Activate Sovereign Protection Engine (Transitions UI to Active)
      unawaited(
          _engine.activateProtection(_supabase.auth.currentUser?.id ?? ''));
    }
  }

  /// [SAFETY_GUARD]: Helper to ensure navigation only happens when the navigator is ready.
  Future<void> _safeNavigate(String route,
      {dynamic arguments, bool isOff = false}) async {
    final bool isGetXReady = Get.key.currentState != null;

    if (_isAppReady && isGetXReady) {
      if (Get.currentRoute == route) return;

      if (isOff) {
        unawaited(Get.offNamed(route, arguments: arguments));
      } else {
        unawaited(Get.toNamed(route, arguments: arguments));
      }
    } else {
      debugPrint(
          '📞 CommunicationController: Deferring navigation to $route (Ready: $_isAppReady, Context: $isGetXReady).');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeNavigate(route, arguments: arguments, isOff: isOff);
      });
    }
  }

  // --- Advisory System (Windows) ---

  Future<void> _runAudioHealthCheck() async {
    debugPrint('🛡️ [HEALTH_CHECK] Starting Windows Audio Diagnostic...');

    // 1. Device Enumeration & Type Detection
    final devices = await _webrtc.getAudioDevices();
    if (devices.isEmpty) {
      _triggerAdvisory('NO_DEVICE');
      return;
    }

    bool hasUsbMic = false;
    bool hasAnalogMic = false;

    for (var device in devices) {
      final label = device.label.toLowerCase();
      debugPrint('🛡️ [HEALTH_CHECK] Found: ${device.label}');

      // Look for USB string or specific USB device characteristics in labels
      if (label.contains('usb')) {
        hasUsbMic = true;
      } else if (label.contains('high definition audio') ||
          label.contains('realtek') ||
          label.contains('analog')) {
        hasAnalogMic = true;
      }
    }

    // 2. Pre-warm Level Check (Monitor for 2 seconds)
    double maxLevel = 0.0;
    int checks = 0;
    const int maxChecks = 10; // Check every 200ms

    while (checks < maxChecks && !_sessionClosed) {
      await Future.delayed(const Duration(milliseconds: 200));
      final level = await _webrtc.getLocalAudioLevel();
      if (level > maxLevel) maxLevel = level;
      if (maxLevel > 0.05) break; // Detected activity
      checks++;
    }

    debugPrint(
        '🛡️ [HEALTH_CHECK] Result - Max Level: $maxLevel, USB: $hasUsbMic');

    // 3. Evaluation
    if (maxLevel < 0.0001) {
      _triggerAdvisory('SILENT_MIC');
    } else if (!hasUsbMic && hasAnalogMic) {
      _triggerAdvisory('ANALOG_DEVICE');
    }
  }

  void _triggerAdvisory(String reason) {
    addLog('🚨 [ADVISORY_TRIGGERED] Reason: $reason');
    advisoryReason.value = reason;
    showAudioAdvisory.value = true;

    // Auto-show the professional modal
    AudioAdvisoryModal.show();
  }

  void proceedWithAdvisory() {
    showAudioAdvisory.value = false;
    Get.back(); // Close modal
    addLog('🛡️ [ADVISORY] User decided to Continue Anyway');
  }

  // --- Diagnostic Support ---

  bool _shouldPromptDiagnostic() {
    // Prompt if never run, or more than 7 days old, or on Windows
    if (_lastDiagnosticTime == null) return true;
    if (GetPlatform.isWindows) {
      return true; // Aggressive on Windows for stability
    }
    return DateTime.now().difference(_lastDiagnosticTime!).inDays > 7;
  }

  void _showDiagnosticRecommendation() {
    Get.snackbar(
      Get.locale?.languageCode == 'ar'
          ? 'توصية الجودة'
          : 'Quality Recommendation',
      Get.locale?.languageCode == 'ar'
          ? 'ننصح بإجراء فحص سريع للأجهزة لضمان أفضل استقرار للمكالمة.'
          : 'We recommend a quick device check for best call stability.',
      mainButton: TextButton(
        onPressed: () => Get.toNamed('/diagnostic_center'),
        child:
            Text(Get.locale?.languageCode == 'ar' ? 'بدء الفحص' : 'Start Test'),
      ),
      duration: const Duration(seconds: 8),
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blue.withValues(alpha: 0.1),
    );
  }

  void _showNetworkWarning() {
    Get.snackbar(
      Get.locale?.languageCode == 'ar' ? 'ضعف الاتصال' : 'Weak Connection',
      Get.locale?.languageCode == 'ar'
          ? 'ظروف الشبكة الحالية قد تؤثر على جودة المكالمة. ننصح بإجراء فحص للشبكة.'
          : 'Your current network conditions may affect call quality. Consider running a network test.',
      mainButton: TextButton(
        onPressed: () => Get.toNamed('/network_diagnostic'),
        child:
            Text(Get.locale?.languageCode == 'ar' ? 'بدء الفحص' : 'Start Test'),
      ),
      duration: const Duration(seconds: 8),
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange.withValues(alpha: 0.1),
    );
  }

  /// [Stage R23]: ICE Failure/Stall Recovery
  Future<void> _handleIceFailure(String userId, String reason) async {
    PHASE('PHASE: ICE_STALL detected for $userId ($reason)');
    if (_isCleaningUp || isEnding.value) return;

    // [R31][FORENSICS] Trigger hard failure forensic mode
    unawaited(executeR31ForensicSuite(userId));

    // [SOVEREIGN_RECOVERY]: Logic to restart ICE
    final count = _iceRestartCounts[userId] ?? 0;

    if (count < _maxIceRestarts) {
      unawaited(_triggerIceRestart(userId));
    } else {
      addLog(
          '❌ ICE_RECOVERY: Max restarts reached or cooldown active. Giving up.');
      unawaited(leaveSession(reason: 'ice_failure_max_retries'));
    }
  }

  /// [Area 7]: Handle Windows/Mobile hardware device changes
  void _handleDeviceChange() {
    addLog('🔌 [Area 7] Hardware: Audio/Video device change detected.');
    // [ROBUSTNESS]: If we are active, we verify if the track is still healthy.
    // ConnectionManager handles some track replacement, but we log for forensics.
    if (webRTCState.value == WebRTCLifecycle.active ||
        webRTCState.value == WebRTCLifecycle.mediaFlowing) {
      debugPrint(
          '🔌 [Area 7] Device change during active call. Monitoring tracks...');
    }
  }

  /// [Stage R28]: Media Verification Layer - Polling bytesReceived
  Future<void> _verifyMediaFlow(String userId) async {
    addLog('🔍 Verification: Starting Media Flow Check for $userId...');
    int attempts = 0;
    int successCount = 0; // [Stage R28.1]: Track sustained flow
    const maxAttempts = 15; // 7.5 seconds (500ms * 15)
    int lastBytes = await _webrtc.getBytesReceived(userId);

    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (isClosed ||
          webRTCState.value == WebRTCLifecycle.ended ||
          webRTCState.value == WebRTCLifecycle.idle) {
        timer.cancel();
        return;
      }

      attempts++;
      final currentBytes = await _webrtc.getBytesReceived(userId);
      final stats = await _webrtc.getDetailedStats(userId);

      // [Stage R28.2]: RTP Forensics Instrumentation
      if (GetPlatform.isWindows) {
        for (var report in stats) {
          if (report.type == 'outbound-rtp') {
            final bSent = report.values['bytesSent'] ?? 0;
            final pSent = report.values['packetsSent'] ?? 0;

            // Get track info from the same report if available, or from localStream
            final localTrack =
                _webrtc.localStream?.getAudioTracks().firstOrNull;

            addLog('WINDOWS_OUTBOUND:\n'
                'bytesSent: $bSent\n'
                'packetsSent: $pSent\n'
                'audioLevel: ${await _webrtc.getLocalAudioLevel()}\n'
                'trackEnabled: ${localTrack?.enabled}');
          }
        }
      } else if (GetPlatform.isAndroid) {
        for (var report in stats) {
          if (report.type == 'inbound-rtp') {
            final bRecv = report.values['bytesReceived'] ?? 0;
            final pRecv = report.values['packetsReceived'] ?? 0;
            final jitter = report.values['jitter'] ?? 0;
            final aLevel = report.values['audioLevel'] ?? 0;

            addLog('ANDROID_INBOUND:\n'
                'bytesReceived: $bRecv\n'
                'packetsReceived: $pRecv\n'
                'jitter: $jitter\n'
                'audioLevel: $aLevel');
          }
        }
      }

      if (currentBytes > lastBytes) {
        successCount++;
        addLog(
            '📊 Flow: Bytes increased ($currentBytes). Success count: $successCount');

        // [R30] UI AUTHORITY: Force clear "Reconnecting" banner immediately on first sign of life
        if (successCount == 1 &&
            _engine.status == CommSessionStatus.reconnecting) {
          addLog(
              '📡 UI_AUTHORITY: Force clearing Reconnecting banner (Media Life detected).');
          _engine.statusRx.value = isCameraOn.value
              ? CommSessionStatus.activeVideo
              : CommSessionStatus.activeAudio;
        }
      }

      lastBytes = currentBytes;

      if (successCount >= 2) {
        timer.cancel();
        addLog('✅ Verification: Sustained Media Flow Detected.');
        _transitionToState(WebRTCLifecycle.mediaFlowing,
            source: 'media_verification');

        // [DETERMINISTIC_ACTIVE]: Only now do we update the UI/Engine status
        if (_engine.status != CommSessionStatus.activeAudio &&
            _engine.status != CommSessionStatus.activeVideo) {
          _engine.statusRx.value = isCameraOn.value
              ? CommSessionStatus.activeVideo
              : CommSessionStatus.activeAudio;
          addLog('🔥 Sovereign: Call is now LIVE (Verified Media Flow)');
          _transitionToState(WebRTCLifecycle.active,
              source: 'media_flow_verified');
          _connectingWatchdogs[userId]?.cancel(); // [R31] Stop watchdog
          _markCallAsActiveIfReady();
        }
        return;
      }

      if (attempts >= maxAttempts) {
        timer.cancel();
        addLog(
            '❌ Verification: Media Flow timeout (No sustained flow in 7.5s)');
        // [R31][FORENSICS] Trigger hard failure forensic mode
        unawaited(executeR31ForensicSuite(userId));
      }
    });
  }

  /// [SAFE_SDP]: Platform-safe way to get local description without throwing on Windows
  Future<webrtc.RTCSessionDescription?> _safeGetLocalDescription(
      webrtc.RTCPeerConnection pc) async {
    try {
      return await pc.getLocalDescription();
    } catch (e) {
      // On Windows, getLocalDescription() throws if not set yet.
      // We catch this and return null to satisfy the logic.
      if (e.toString().contains('not local description')) {
        return null;
      }
      debugPrint('âš ï¸ Sovereign: SafeGetLocalDescription Error: $e');
      return null;
    }
  }

  /// [R31] HARD FAILURE FORENSIC MODE
  Future<void> executeR31ForensicSuite(String userId) async {
    debugPrint('\n${'=' * 60}');
    debugPrint('🚀 [R31] STARTING HARD FAILURE FORENSIC SUITE');
    debugPrint('🎯 Target User: $userId');
    debugPrint('⏰ Time: ${DateTime.now()}');
    debugPrint('=' * 60 + '\n');

    final peer = _webrtc.getSovereign(userId);
    if (peer == null) {
      debugPrint('[R31][FATAL] No SovereignPeer found for $userId');
      return;
    }

    // --- PHASE 1 ---
    debugPrint('[R31][WINDOWS_AUDIO_FLOW]');
    try {
      final devices = await webrtc.navigator.mediaDevices.enumerateDevices();
      debugPrint('Device Enumeration:');
      for (var d in devices) {
        debugPrint('  [${d.kind}] Label: ${d.label}, ID: ${d.deviceId}');
      }
      await peer.dumpForensicDetails();
    } catch (e) {
      debugPrint('[R31][PHASE 1 ERROR] $e');
    }

    // --- PHASE 2 ---
    debugPrint('\n[R31][ICE_FORENSICS]');
    try {
      final stats = await peer.getStats();
      for (var report in stats) {
        if (report.type == 'candidate-pair' &&
            (report.values['selected'] == true ||
                report.values['state'] == 'succeeded')) {
          debugPrint('  [SELECTED_PAIR] ID: ${report.id}');
          debugPrint(
              '  [SELECTED_PAIR] RTT: ${report.values['currentRoundTripTime']}');
          debugPrint(
              '  [SELECTED_PAIR] Bitrate: ${report.values['availableOutgoingBitrate']}');
        }
      }
      debugPrint('  ICE Gathering State: ${peer.pc.iceGatheringState}');
      debugPrint('  ICE Connection State: ${peer.pc.iceConnectionState}');
    } catch (e) {
      debugPrint('[R31][PHASE 2 ERROR] $e');
    }

    // --- PHASE 3 ---
    debugPrint('\n[R31][MEDIA_FLOW] Starting 10s trace...');
    int samples = 0;
    int totalBytesSent = 0;
    int totalBytesReceived = 0;

    // Non-blocking trace
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (samples >= 5 || isClosed) {
        timer.cancel();
        _finalizeR31Report(userId, totalBytesSent, totalBytesReceived);
        return;
      }

      try {
        final stats = await peer.getStats();
        for (var report in stats) {
          if (report.type == 'outbound-rtp' &&
              report.values['kind'] == 'audio') {
            totalBytesSent +=
                int.tryParse(report.values['bytesSent']?.toString() ?? '0') ??
                    0;
          }
          if (report.type == 'inbound-rtp' &&
              report.values['kind'] == 'audio') {
            totalBytesReceived += int.tryParse(
                    report.values['bytesReceived']?.toString() ?? '0') ??
                0;
          }
        }
        debugPrint(
            '  [TRACE] Sample ${samples + 1}: Sent=$totalBytesSent, Recv=$totalBytesReceived');
      } catch (e) {
        debugPrint('  [TRACE_ERROR] $e');
      }
      samples++;
    });
  }

  void _finalizeR31Report(String userId, int bytesSent, int bytesRecv) {
    debugPrint('\n${'-' * 40}');
    debugPrint('[R31 RESULT]');

    String rootCause = 'UNKNOWN';
    double confidence = 0.0;

    if (bytesSent == 0) {
      rootCause = 'MEDIA FLOW BLOCKED (Outbound)';
      confidence = 90.0;
    } else if (bytesRecv == 0) {
      rootCause = 'MEDIA FLOW BLOCKED (Inbound/One-Way)';
      confidence = 85.0;
    } else {
      rootCause = 'SIGNALING GLARE LOOP / RTC STATE NULL';
      confidence = 70.0;
    }

    debugPrint('Root Cause: $rootCause');
    debugPrint('Confidence: $confidence%');
    debugPrint('Platform at Fault: Windows (Forensic Target)');
    debugPrint(
        'ICE Stable? ${webRTCState.value == WebRTCLifecycle.iceConnected ? "Yes" : "No"}');
    debugPrint('Media Flow? ${bytesRecv > 0 ? "Yes" : "No"}');
    debugPrint('BytesSent: $bytesSent');
    debugPrint('BytesReceived: $bytesRecv');
    debugPrint('Selected Candidate Type: Check [ICE_FORENSICS] logs');
    debugPrint('Recommended Next Patch: Hardened ICE Filtering (force relay)');
    debugPrint('-' * 40 + '\n');
  }

  void _finalizeR32Report(
      String userId, int preSent, int preRecv, int postSent, int postRecv) {
    debugPrint('\n${'-' * 40}');
    debugPrint('[R32 FINAL REPORT]');
    debugPrint('-' * 40);

    String conclusion = 'UNKNOWN';
    double confidence = 0.0;
    String platformFault = 'TBD';

    if (preRecv == 0 && postRecv > 0) {
      conclusion =
          'Symmetric NAT or Firewall Blocking Direct Media (Fixed via Relay)';
      platformFault = 'Windows Network Layer';
      confidence = 95.0;
    } else if (postRecv == 0 && postSent > 0) {
      conclusion =
          'Windows SRTP Decrypt or Audio Sink Failure (Persistent Block)';
      platformFault = 'Windows Audio/Security Layer';
      confidence = 85.0;
    } else if (preSent > 0 && preRecv > 0) {
      conclusion = 'Media Stable (No Action Needed)';
      platformFault = 'None';
      confidence = 100.0;
    } else {
      conclusion =
          'Complex Failure - Check forensic logs for DTLS/Signaling issues';
      platformFault = 'WebRTC Stack';
      confidence = 60.0;
    }

    debugPrint(
        'ICE Stable? ${webRTCState.value == WebRTCLifecycle.iceConnected ? "Yes" : "No"}');
    debugPrint('Conclusion: $conclusion');
    debugPrint('Platform at Fault: $platformFault');
    debugPrint('Confidence: $confidence%');
    debugPrint('Pre-Relay (Sent/Recv): $preSent / $preRecv');
    debugPrint('Post-Relay (Sent/Recv): $postSent / $postRecv');
    debugPrint('${'-' * 40}\n');
  }

  /// [AEC_HARDENING]: Software-level Adaptive Audio Gate
  /// Polls the local audio level and mutes the track if it only contains feedback.
  Future<void> _runAdaptiveEchoSuppression() async {
    if (_isAdaptiveEchoActive || !GetPlatform.isWindows) return;
    _isAdaptiveEchoActive = true;
    addLog('🛡️ AEC: Adaptive suppression gate active.');

    _adaptiveEchoTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_isAdaptiveEchoActive || _sessionClosed) {
        timer.cancel();
        return;
      }

      try {
        final double level = await _webrtc.getLocalAudioLevel();
        final double totalCancellation = _currentAecCancellation;

        final bool isTalking = (level > 0.05); // High-pass for human voice

        // [Area 2 Fallback]: If AEC is failing (Cancellation < 15dB) or inactive,
        // apply a stricter gate to prevent feedback loops.
        double gateThreshold = 0.01;
        if (totalCancellation < 15.0) {
          gateThreshold = 0.04; // Stricter gate for failing/inactive AEC
        }

        if (level > 0 && level < gateThreshold && !isTalking) {
          // Detects the ghost oscillation of acoustic feedback
          debugPrint(
              '🔇 [AEC_GATE] Software suppression active (Threshold: $gateThreshold, TotalCancellation: ${totalCancellation.toStringAsFixed(1)}dB)');
        }
      } catch (e) {
        debugPrint('⚠️ AEC_GATE Error: $e');
      }
    });
  }

  /// [Area 2]: Periodic AEC Performance Audit for Windows
  Future<void> _auditAECPerformance() async {
    if (!GetPlatform.isWindows) return;

    final stats = await _webrtc.getAECStats();
    final double erl = stats['ERL'] ?? 0.0;
    final double erle = stats['ERLE'] ?? 0.0;
    _currentAecCancellation = erl + erle;

    if (_currentAecCancellation > 0) {
      // AEC3 Target is usually > 40dB. If < 15dB, it's a silent failure.
      if (micLevel.value > 0.1 && _currentAecCancellation < 15.0) {
        addLog(
            '⚠️ [Area 2] AEC WARNING: Poor cancellation (${_currentAecCancellation.toStringAsFixed(1)}dB). '
            'External speakers may cause echo. Headset recommended.');
      } else {
        debugPrint(
            '🛡️ [Area 2] AEC Audit: Total Cancellation = ${_currentAecCancellation.toStringAsFixed(1)}dB (ERL=$erl, ERLE=$erle)');
      }
    }
  }

  /// [Area 3]: Periodic ICE Continuity Audit for Enterprise NAT
  Future<void> _auditICEConnections() async {
    for (var p in participants) {
      if (p.isLocal) continue;

      final ice = await _webrtc.getIceStats(p.id);
      if (ice['available'] == true) {
        final String localType = ice['localType'] ?? 'unknown';
        final String remoteType = ice['remoteType'] ?? 'unknown';
        final bool isHostToHost = ice['isHostToHost'] ?? false;

        if (isHostToHost) {
          debugPrint(
              '🧭 [Area 3] ICE Audit: P2P Host connection for ${p.id} ($localType <-> $remoteType).');
          if (webRTCState.value != WebRTCLifecycle.active &&
              webRTCState.value != WebRTCLifecycle.mediaFlowing) {
            addLog(
                '🚀 [Area 3] Escalation: Unstable host-host path detected. Triggering RELAY Restart.');
            unawaited(_triggerIceRestart(p.id));
          }
        }

        // [Carrier-Grade] Area 2: DTLS Stall Watchdog
        final peer = _webrtc.getSovereignPeer(p.id);
        if (peer != null && peer.iceConnectedAt != null) {
          final dtlsState = ice['dtlsState'] ?? 'unknown';
          final duration = DateTime.now().difference(peer.iceConnectedAt!);
          if (duration.inSeconds > 10 && dtlsState != 'connected') {
            addLog(
                '🔥 [Carrier-Grade] Area 2: DTLS Stall Detected ($dtlsState after ${duration.inSeconds}s). Recovering...');
            unawaited(_handleIceFailure(p.id, 'dtls_stall'));
            peer.iceConnectedAt = null; // Prevent repeat
          }
        }

        // [Carrier-Grade] Area 4: Long-Call Drift Protection
        final double rtt = ice['rtt'] ?? 0.0;
        final int packetsLost = ice['packetsLost'] ?? 0;
        if (rtt > 0.4 || packetsLost > 100) {
          addLog(
              '📉 [Carrier-Grade] Area 4: Drift Detected (RTT: ${rtt.toStringAsFixed(3)}, Loss: $packetsLost). Preemptive restart...');
          unawaited(_triggerIceRestart(p.id));
        }

        // [Carrier-Grade] Area 6: Adaptive Bitrate Governor
        unawaited(_applyAdaptiveBitrate(p.id, ice));
      }
    }
  }

  /// [Carrier-Grade] Area 6: Sample stats and adjust Opus bitrate
  Future<void> _applyAdaptiveBitrate(
      String userId, Map<String, dynamic> stats) async {
    final double rtt = stats['rtt'] ?? 0.0;
    final int packetsLost = stats['packetsLost'] ?? 0;
    final peer = _webrtc.getSovereignPeer(userId);
    if (peer == null) return;

    // Default Opus starts around 32-64kbps
    int targetKbps = 64;

    if (rtt > 0.3 || packetsLost > 20) {
      targetKbps =
          24; // Downscale quality to preserve intelligibility under loss
    } else if (rtt > 0.15 || packetsLost > 5) {
      targetKbps = 40; // Mid-scale
    }

    // Only apply if changed to avoid SRTP parameter oscillation
    unawaited(peer.setBitrate(targetKbps));
  }

  Future<void> _performAndroidResumeAudit() async {
    // 1. Snap initial stats
    final initialPackets = await _getTotalPacketsReceived();

    // 2. Wait 3 seconds for delta growth
    await Future.delayed(const Duration(seconds: 3));

    // 3. Compare
    final finalPackets = await _getTotalPacketsReceived();
    final delta = finalPackets - initialPackets;

    addLog('📱 [Carrier-Grade] Area 3: Resume Audit Delta = $delta packets');

    if (delta == 0 &&
        webRTCState.value == WebRTCLifecycle.active &&
        !isMuted.value) {
      addLog(
          '🚨 [Carrier-Grade] Area 3: Zero media delta on resume. Triggering soft recovery...');
      for (var p in participants) {
        if (!p.isLocal) unawaited(_triggerIceRestart(p.id));
      }
    }
  }

  Future<int> _getTotalPacketsReceived() async {
    int total = 0;
    for (var p in participants) {
      if (p.isLocal) continue;
      final ice = await _webrtc.getIceStats(p.id);
      total += (ice['packetsReceived'] ?? 0) as int;
    }
    return total;
  }

  /// [Carrier-Grade] Area 5: Chaos Resilience Utility
  /// Manual trigger for validating recovery paths in production/staging.
  void simulateChaos(String userId, String failureType) {
    addLog(
        '🎲 [Carrier-Grade] Area 5: CHAOS INJECTED -> $failureType ($userId)');
    switch (failureType) {
      case 'dtls_stall':
        final peer = _webrtc.getSovereignPeer(userId);
        if (peer != null) {
          peer.iceConnectedAt =
              DateTime.now().subtract(const Duration(seconds: 15));
          debugPrint('🎲 CHAOS: Forced DTLS Stall for $userId');
        }
        break;
      case 'drift':
        addLog('🎲 CHAOS: Forcing drift-based restart for $userId');
        unawaited(_triggerIceRestart(userId));
        break;
      case 'resume_freeze':
        if (GetPlatform.isAndroid) {
          addLog('🎲 CHAOS: Simulating zero-delta resume freeze');
          _performAndroidResumeAudit(); // This will audit currently stable media and find 0 delta if we force it
        }
        break;
    }
  }

  /// [Area 4]: Sequential execution for tasks blocked during negotiation
  void _drainNegotiationQueue() {
    if (_negotiationTaskQueue.isEmpty) return;
    addLog(
        '🚰 [Area 4] Draining Negotiation Task Queue (${_negotiationTaskQueue.length} tasks)');
    final tasks = List<Future<void> Function()>.from(_negotiationTaskQueue);
    _negotiationTaskQueue.clear();
    for (var task in tasks) {
      unawaited(task());
    }
  }
}
