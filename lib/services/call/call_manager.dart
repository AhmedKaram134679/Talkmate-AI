import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rxdart/rxdart.dart' hide Rx;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/clients/call_feature_client.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/communication/call_notification_manager.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/services/audio/app_audio_service.dart';
import 'package:talkmate_ai/services/call/foreground_service.dart';
import 'package:window_manager/window_manager.dart';

/// [STAGE CALLS]: Central Call Manager for TalkMate AI.
/// Responsible for:
/// 1. Global Call State (idle | incoming | outgoing | active).
/// 2. Ensuring only ONE call session exists at a time.
/// 3. Navigation management for calls.
/// 4. Global signaling orchestration.
class CallManager extends GetxService
    with WidgetsBindingObserver, WindowListener {
  CallManager._();
  static final CallManager instance = CallManager._();

  final _auth = Get.find<AuthController>();
  final _repo = Get.find<ICallRepository>();
  final _engine = SovereignCommunicationEngine.instance;

  // Reactive State
  final Rx<CallSession?> currentSession = Rx<CallSession?>(null);
  final Rx<CallStatus> callStatus = CallStatus.ended.obs;
  final Set<String> _shownCalls = {}; // Track shown calls in this session
  DateTime? _callStartTime;
  bool isIncoming = false; // [MANDATORY_FIX]: Explicit pathway separation
  bool _isAppReady =
      false; // [SAFETY_GUARD]: Flag to prevent early navigation crashes

  Timer? _timeoutTimer;
  bool _isTerminating = false; // [HARDENING]: Prevent global termination loops

  // Tag for the active controller
  String get activeTag =>
      currentSession.value != null ? 'webrtc_${currentSession.value!.id}' : '';

  // Listeners
  StreamSubscription? _signalingSub;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.addListener(this);
    }
    _setupAuthListener();
    unawaited(_checkCallIntent());
    _ensureNavigatorReady();
    return;
  }

  void _ensureNavigatorReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.key.currentState != null) {
        debugPrint('📞 CallManager: App Navigator is ready.');
        _isAppReady = true;
      } else {
        // Retry until navigator is actually bound to GetMaterialApp
        _ensureNavigatorReady();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCallIntent();
    } else if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      // Small safety check - ensure sounds stop if app is being murdered by OS
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        // On Windows, sounds usually stop when process dies, but we can be proactive
        debugPrint('📞 CallManager: Window state changed to $state');
      }
    }
  }

  @override
  Future<void> onWindowClose() async {
    debugPrint('📞 CallManager: Window closed by user. Cleaning up...');
    await terminateCall(securityContext: currentSession.value?.id);
  }

  Future<void> _checkCallIntent() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        const channel = MethodChannel('com.example.talkmate_ai/call_intent');
        final Map<dynamic, dynamic>? data =
            await channel.invokeMethod('getCallIntent');

        if (data != null) {
          debugPrint('📞 CallManager: Intent detected: $data');
          final callId = data['callId'] as String;
          final otherId = data['otherId'] as String;
          final isIncoming = data['isIncoming'] as bool;
          final isVideo = data['isVideo'] as bool;

          // [Architecture Fix]: Confirmation Ping (Startup Gate)
          try {
            debugPrint('🛡️ CallManager: Verifying intent for $callId...');
            final call = await _repo.getById(callId);
            if (call == null ||
                (call.status != CallStatus.ringing &&
                    call.status != CallStatus.ongoing &&
                    call.status != CallStatus.accepted)) {
              debugPrint(
                  '🛑 Startup Gate: Ignoring inactive intent for $callId (Status: ${call?.status.name})');
              return;
            }
          } catch (e) {
            debugPrint(
                '⚠️ Startup Gate: Validation failed ($e). Proceeding with caution...');
            return; // Fail safe
          }

          final route = data['route'] as String? ?? '/call_ringing';

          // Prevent duplicate navigation if we are already there
          if (Get.currentRoute == route) return;

          // If the call is already ended in our state but the intent is old, ignore
          // But if we have no session, we should probably fetch it or trust the intent

          await _safeNavigate(route, arguments: {
            'callId': callId,
            'otherId': otherId,
            'isIncoming': isIncoming,
            'isVideo': isVideo,
          });
        }
      } catch (e) {
        debugPrint('CallManager: Error checking call intent: $e');
      }
    }
  }

  void _setupAuthListener() {
    ever(_auth.isLoggedInRx, (loggedIn) {
      if (loggedIn) {
        _startSignaling();
      } else {
        _stopSignaling();
      }
    });

    if (_auth.isLoggedIn) {
      _startSignaling();
    }

    // Handle token refreshes to ensure signaling uses the new JWT
    // [Stage R]: Debounced Signaling Restart to avoid storming
    Timer? refreshDebounce;
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.tokenRefreshed) {
        if (_auth.isLoggedIn) {
          refreshDebounce?.cancel();
          refreshDebounce = Timer(const Duration(seconds: 1), () {
            debugPrint(
                'CallManager: Token refreshed, re-starting signaling (Debounced).');
            _startSignaling();

            // [Sovereign Recovery]: Poke CommunicationController to refresh its active stream
            if (Get.isRegistered<CommunicationController>()) {
              Get.find<CommunicationController>().refreshSignaling();
            }
          });
        }
      }
    }, onError: (e) {
      debugPrint('CallManager: Auth state change error: $e');
    });
  }

  void _startSignaling() {
    _signalingSub?.cancel();
    _shownCalls.clear();

    final userId = _auth.userId;
    if (userId.isEmpty) return;

    _signalingSub = RetryWhenStream(
      () => _repo.watchUserCalls(userId),
      (error, stackTrace) {
        debugPrint('CallManager: Signaling retry due to error: $error');
        if (AppConfig.isStaleSessionError(error)) {
          AppLogger.warning(
              'CallManager: Signaling channel error, triggering recovery.',
              context: {'error': error.toString()});
          unawaited(_auth.recoverSession());
        }
        return Stream.value(null).delay(const Duration(seconds: 5));
      },
    ).listen((calls) {
      if (!AppConfig.globalCallsEnabled) return;

      for (final call in calls) {
        // [GLOBAL_END_LISTENER]: Mandatory immediate cleanup for terminal statuses
        if (call.status == CallStatus.ended ||
            call.status == CallStatus.rejected ||
            call.status == CallStatus.missed ||
            call.status == CallStatus.failed) {
          if (currentSession.value?.id == call.id &&
              callStatus.value != CallStatus.ended) {
            debugPrint(
                '📞 CallManager: TERMINAL STATE detected via DB for ${call.id}. Closing all.');
            unawaited(terminateCall(status: call.status, fromRemote: true));
          }
          continue;
        }

        // [STALENESS_GUARD]: Ignore active calls older than 5 minutes if we aren't already in them.
        // This prevents "Ghost Calls" (old calls stuck in active status in DB) from triggering UI on app start.
        // [FIX]: We only guard against PAST calls (age > 0). Future calls (age < 0) are likely clock drift and should be processed.
        final age = DateTime.now().difference(call.createdAt);
        if (age.inSeconds > 300 && currentSession.value?.id != call.id) {
          // Silent skip for stale records to keep console clean
          continue;
        }

        // 1. Handle OUTGOING calls that are ACCEPTED (We are the Caller)
        if (call.senderId == userId &&
            (call.status == CallStatus.accepted ||
                call.status == CallStatus.ongoing)) {
          // If we are already connected, skip
          if (currentSession.value?.id == call.id &&
              (callStatus.value == CallStatus.ongoing)) {
            continue;
          }

          debugPrint('📞 CallManager: Outgoing call ${call.id} ACCEPTED.');
          handleOutgoingAccepted(call);
          continue;
        }

        // 2. Handle INCOMING calls (Strict DB Listener Only)
        if (call.receiverId == userId && call.status == CallStatus.ringing) {
          // Prevent double processing or overlapping calls
          if (_shownCalls.contains(call.id)) continue;
          if (currentSession.value != null &&
              callStatus.value != CallStatus.ended) {
            continue; // Busy
          }

          handleIncomingCall(call);
        }
      }
    }, onError: (e) {
      debugPrint('CallManager: Signaling subscription fatal error: $e');
    });
  }

  void _stopSignaling() {
    _signalingSub?.cancel();
    _signalingSub = null;
    _shownCalls.clear();
  }

  @override
  void onClose() {
    debugPrint('📞 CallManager: Service onClose (Permanent Cleanup)');
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.removeListener(this);
    }
    unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
    unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
    unawaited(stopNativeRingtone());
    _signalingSub?.cancel();
    stopTimeoutTimer();
    super.onClose();
  }

  Future<void> handleIncomingCall(CallSession session) async {
    // [GOVERNANCE]: Check with FeatureAssimilationLayer
    final callClient = Get.find<CallFeatureClient>();
    final canAccept = await callClient.startCall(session.id, [session.senderId],
        activateMedia: false);

    if (!canAccept) {
      debugPrint('🛑 CallManager: Incoming call REJECTED by Governance.');
      await updateCallStatus(session.id, CallStatus.rejected);
      return;
    }

    _shownCalls.add(session.id);
    currentSession.value = session;
    callStatus.value = CallStatus.ringing;
    isIncoming = true; // [MANDATORY_FIX]: Explicit pathway separation

    // Fetch caller profile for UI
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', session.senderId)
        .maybeSingle();
    final callerName =
        profile?['full_name'] ?? profile?['username'] ?? 'مستخدم TalkMate';

    // [SOVEREIGN]: Request Lock & Ringing
    final metadata = CommSessionMetadata(
      sessionId: session.id,
      type: CommunicationSessionType.call,
      callerName: callerName,
      participantId: session.senderId,
      isVideo: session.isVideo,
    );
    final locked = await _engine.requestSessionLock(
        session.id, CommunicationSessionType.call,
        metadata: metadata);
    if (!locked) return;

    // [SIGNALING_FIX]: Ensure CommunicationController is subscribed IMMEDIATELY
    // This allows receiving "Cancel" signals and sending "Reject" signals via Realtime.
    CommunicationController ctrl;
    if (Get.isRegistered<CommunicationController>()) {
      ctrl = CommunicationController.instance;
    } else {
      ctrl = Get.put(CommunicationController(), permanent: true);
    }
    ctrl.sessionId.value = session.id;
    ctrl.sessionType.value = CommunicationSessionType.call;
    ctrl.manualSubscribe(session.id);

    await _engine.startRinging(session.id, CommunicationSessionType.call, true,
        metadata: metadata);

    // Show native CallKit UI
    await CallNotificationManager.instance.showIncomingCall(
      sessionId: session.id,
      senderId: session.senderId,
      senderName: callerName,
      avatar: profile?['avatar_url'],
      isVideo: session.isVideo,
    );

    // [STRICT AUDIO ENFORCEMENT]: Android Native Ringtone is disabled.
    // We must manually trigger the asset playback here.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      debugPrint('🎵 CallManager: Enforcing Asset Playback for Android...');
      await AppAudioService.instance.stopAll();
      unawaited(AppAudioService.instance.play('call_ringtone.mp3', loop: true));
    }

    // Signal UI to show Incoming Screen
    _engine.statusRx.value = CommSessionStatus.ringingIncoming;

    unawaited(_safeNavigate('/call_ringing', arguments: {
      'callId': session.id,
      'otherId': session.senderId,
      'isIncoming': true,
      'isVideo': session.isVideo,
    }));

    // [WINDOWS HARDENING]: Force show/focus for incoming call
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.setSkipTaskbar(false);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    }

    _startTimeoutTimer(session.id, isIncoming: true);
  }

  Future<void> handleOutgoingAccepted(CallSession session) async {
    _timeoutTimer?.cancel();

    // Update local state
    callStatus.value = CallStatus.ongoing;
    currentSession.value = session;

    // Transition Engine
    _engine.statusRx.value = CommSessionStatus.connecting;

    // Stop Ringback
    await AppAudioService.instance.stop('call_incomming.mp3');

    // [STABILIZATION]: Sync with CommunicationController immediately
    if (Get.isRegistered<CommunicationController>()) {
      final ctrl = Get.find<CommunicationController>();
      ctrl.sessionId.value = session.id;
      ctrl.sessionType.value = CommunicationSessionType.call;
      ctrl.isCameraOn.value = session.isVideo;
      ctrl.sessionName.value = session.isVideo
          ? 'Video Call'
          : 'Audio Call'; // Ensure sessionName is set
      ctrl.manualSubscribe(session.id);
    }
    if (Get.currentRoute != '/communication_live') {
      unawaited(_safeNavigate('/communication_live',
          arguments: {
            'sessionId': session.id,
            'type': CommunicationSessionType.call,
            'isInitiator': true,
            'isVideo': session.isVideo,
          },
          isOff:
              true)); // [FIX] Replace Ringing Screen to prevent auto-pop issues
    }
  }

  Future<void> stopNativeRingtone() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        const channel = MethodChannel('com.example.talkmate_ai/call_intent');
        await channel.invokeMethod('stopRingtone');
      } catch (e) {
        debugPrint('CallManager: Failed to stop native ringtone: $e');
      }
    }
  }

  void _startTimeoutTimer(String sessionId, {required bool isIncoming}) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 45), () async {
      if (currentSession.value?.id == sessionId) {
        final status = callStatus.value;
        final engineStatus = _engine.status;

        // Prevent timeout if we are already accepted, ongoing, or connecting (ICE phase)
        if (status == CallStatus.ringing &&
            engineStatus != CommSessionStatus.connecting &&
            engineStatus != CommSessionStatus.activeAudio &&
            engineStatus != CommSessionStatus.activeVideo) {
          debugPrint('CallManager: Call $sessionId timed out (Still Ringing).');

          // [SIGNALING_FIX]: Broadcast explicit rejection signal via Realtime
          // This ensures Android receives the call_end event even if DB stream is slow.
          if (Get.isRegistered<CommunicationController>()) {
            Get.find<CommunicationController>()
                .sendTerminationSignal(sessionId, reason: 'timeout');
          }

          await updateCallStatus(
              sessionId, isIncoming ? CallStatus.missed : CallStatus.rejected);
          await terminateCall(reason: 'timeout');
        } else {
          debugPrint(
              'CallManager: Timeout bypassed (Status: ${status.name}, Engine: ${engineStatus.name})');
        }
      }
    });
  }

  void stopTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void resumeTimeout(String sessionId) {
    if (currentSession.value?.id == sessionId &&
        callStatus.value != CallStatus.ongoing &&
        callStatus.value != CallStatus.ended) {
      debugPrint('CallManager: Resuming timeout due to connectivity issues.');
      final isIncoming = currentSession.value?.senderId !=
          Supabase.instance.client.auth.currentUser?.id;
      _startTimeoutTimer(sessionId, isIncoming: isIncoming);
    }
  }

  /// Start an outgoing call (Pathway 1)
  Future<void> startOutgoingCall(
      {required String calleeId, required bool isVideo}) async {
    // [SOVEREIGN_RECOVERY]: If local session is null but engine is busy, force a cleanup
    // [FIX]: Check BEFORE startCall to avoid cleanup killing the new call's lock
    if (_engine.isBusy && currentSession.value == null) {
      debugPrint(
          '⚠️ CallManager: Engine busy but no local session. Forcing cleanup...');
      await terminateCall(status: CallStatus.ended);
    }

    // [GOVERNANCE]: Check with FeatureAssimilationLayer
    final callClient = Get.find<CallFeatureClient>();
    final canCall = await callClient.startCall(
        'outgoing_${DateTime.now().millisecondsSinceEpoch}', [calleeId],
        activateMedia: true);

    if (!canCall) {
      Get.snackbar(
          'التزام دستوري', 'تم تعليق المكالمة بناءً على قرارات الحوكمة',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (currentSession.value != null && callStatus.value != CallStatus.ended) {
      Get.snackbar('خطأ', 'هناك مكالمة نشطة بالفعل');
      return;
    }

    try {
      // 1. Create Call Record
      isIncoming = false; // [MANDATORY_FIX]: Mark as outgoing session
      final userId = _auth.userId;
      final call = await _repo.createCall(
        senderId: userId,
        receiverId: calleeId,
        isVideo: isVideo,
      );

      final sessionId = call.id;

      // Update Manager State
      currentSession.value = call;
      callStatus.value = CallStatus.ringing;

      // [SOVEREIGN]: Lock resources and start ringing state
      final metadata = CommSessionMetadata(
        sessionId: sessionId,
        type: CommunicationSessionType.call,
        participantId: calleeId,
        isVideo: isVideo,
      );
      final locked = await _engine.requestSessionLock(
          sessionId, CommunicationSessionType.call,
          metadata: metadata);
      if (!locked) return;

      // Prepare CommunicationController (Initiator/Caller side)
      if (Get.isRegistered<CommunicationController>()) {
        final ctrl = Get.find<CommunicationController>();
        unawaited(ctrl.startInitiatorSequence(sessionId, calleeId, isVideo));
      }

      await _engine.startRinging(
          sessionId, CommunicationSessionType.call, false,
          metadata: metadata);

      unawaited(_safeNavigate('/call_ringing', arguments: {
        'callId': sessionId,
        'otherId': calleeId,
        'isIncoming': false,
        'isVideo': isVideo,
      }));

      // [Initiating Signaling Phase]: Only for outgoing calls
      if (!isIncoming) {
        debugPrint(
            '🚀 CallManager: [Initiating Signaling Phase] for outgoing call.');
        _startTimeoutTimer(sessionId, isIncoming: false);
      }
    } catch (e) {
      debugPrint('CallManager: startOutgoingCall failed: $e');
      rethrow;
    }
  }

  /// [CONSTITUTIONAL AUTHORITY]: Centralized method for database status updates.
  /// Only this class should modify the call status to ensure a single reason for state changes.
  Future<void> updateCallStatus(String sessionId, CallStatus status) async {
    debugPrint('🏛️ State Authority: Updating DB -> ${status.name}');
    await _repo.updateStatus(sessionId, status);
  }

  /// Global end call (Unified entry point)
  Future<void> terminateCall({
    CallStatus status = CallStatus.ended,
    bool fromRemote = false,
    String? securityContext,
    String reason = 'manual',
  }) async {
    final session = currentSession.value;
    final sessionId = session?.id ?? 'unknown';

    // [SessionGuard]
    if (securityContext != null &&
        securityContext.isNotEmpty &&
        securityContext != sessionId) {
      debugPrint(
          '🛡️ CallManager Guard: Ignoring terminate for mismatch context ($securityContext vs $sessionId)');
      return;
    }

    // [STATE_GUARD]: Prevent late timeouts from killing active calls
    if (reason == 'timeout' &&
        (callStatus.value == CallStatus.ongoing ||
            callStatus.value == CallStatus.accepted)) {
      debugPrint(
          '🛡️ CallManager Guard: Ignoring TIMEOUT termination because status is ${callStatus.value.name}');
      return;
    }

    if (_isTerminating) return;
    _isTerminating = true;

    debugPrint(
        '📞 CallManager: Global Terminate triggered (Session: $sessionId, Status: $status, Remote: $fromRemote, Reason: $reason)');

    // 1. Stop Ringtones & Notifications IMMEDIATELY
    unawaited(stopNativeRingtone());
    unawaited(CallNotificationManager.instance.endAllCalls());
    unawaited(AppAudioService.instance.stop('call_ringtone.mp3'));
    unawaited(AppAudioService.instance.stop('call_incomming.mp3'));
    stopTimeoutTimer();

    // 2. Clear UI Overlays (Sheets, Dialogs)
    if (_isAppReady && (Get.isOverlaysOpen || Get.isBottomSheetOpen == true)) {
      Get.back();
    }

    // 3. Delegate to CommunicationController for WebRTC & Hardware cleanup
    if (Get.isRegistered<CommunicationController>()) {
      final SessionLifecycle ctrl = Get.find<CommunicationController>();
      // [SYMMETRY_FIX]: Broadcast termination signal to peer if we are the initiator of end
      if (!fromRemote && sessionId != 'unknown') {
        Get.find<CommunicationController>().sendTerminationSignal(sessionId);
      }
      await ctrl.leaveSession(
        reason: fromRemote ? 'remote_terminate' : reason,
        securityContext: sessionId,
      ); // Blocking cleanup

      // [FIX]: Ensure audio is stopped even if ctrl.leaveSession threw or took time
      unawaited(AppAudioService.instance.stopAll());
    }
    _isTerminating = false; // Reset lock after all cascades are done

    // 4. Update DB status if it's not already terminal and we didn't get this from remote
    if (sessionId != 'unknown' &&
        !fromRemote &&
        callStatus.value != CallStatus.ended) {
      unawaited(updateCallStatus(sessionId, status));
    }

    // 5. Release Platform Resources
    unawaited(_engine.endSession(_auth.userId));
    unawaited(CallForegroundService.stop());

    // 6. Visual Transition - Leave call screens
    if (_isAppReady) {
      Get.until((route) {
        final name = route.settings.name;
        // Stop if we hit any base screen
        if (name == '/main' ||
            name == '/chats' ||
            name == '/login' ||
            name == '/onboarding' ||
            name == '/settings' ||
            name == '/calls' ||
            name == '/profile') {
          return true;
        }

        // Stop if it's NOT a call screen
        final routeName = name ?? '';
        final isCallScreen = routeName.contains('call') ||
            routeName.contains('communication') ||
            routeName.contains('IncomingCallScreen') ||
            routeName.contains('CommunicationLiveScreen') ||
            routeName.contains('CallRingingScreen');

        // [HARDENING]: Specifically allow base screens even if they accidentally contain 'call'
        if (routeName == '/main' || routeName == '/chats') return true;

        return !isCallScreen;
      });

      // [FALLBACK]: If we are stuck on a blank screen (last route) or somehow still on a call screen
      // after the flush, forcefully return to the main application wrapper.
      final current = Get.currentRoute;
      final stillOnCall = current.isEmpty ||
          current == '/' ||
          current.contains('call') ||
          current.contains('communication');

      if (stillOnCall) {
        debugPrint(
            '📞 CallManager: Navigation stack exhausted or still on call screen ($current). Force returning to /main.');
        unawaited(Get.offAllNamed(_auth.isLoggedIn ? '/main' : '/login'));
      }
    }

    // [WINDOWS HARDENING]: Ensure we are not stuck on top
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(windowManager.setAlwaysOnTop(false));
      unawaited(windowManager.setSkipTaskbar(false));
    }

    // 7. Reset local state last
    _logMetrics(sessionId, status);
    currentSession.value = null;
    callStatus.value = CallStatus.ended; // Always terminal local state
  }

  /// Accepts the current ringing call (Hardened for background/indirect calls)
  Future<void> acceptCall({String? callId}) async {
    CallSession? session = currentSession.value;

    // [STABILIZATION]: If session is missing (Android background accept), try to restore it
    if (session == null && callId != null) {
      debugPrint(
          '📞 CallManager: [RESTORE] Fetching call $callId for acceptance...');
      session = await _repo.getById(callId);
      if (session != null) {
        currentSession.value = session;
        callStatus.value = CallStatus.ringing;
      }
    }

    if (session == null) {
      debugPrint(
          '🚨 CallManager: acceptCall failed - No active session found.');
      return;
    }

    debugPrint('📞 CallManager: Starting 3-Stage Acceptance Handshake...');

    // Stage 1: Stop bells & whistles
    unawaited(stopNativeRingtone());
    unawaited(CallNotificationManager.instance.endAllCalls());
    stopTimeoutTimer();

    // Stage 2: DB Transition to ACCEPTED
    await updateCallStatus(session.id, CallStatus.accepted);

    // Stage 3: Sovereign Media Preparation
    CommunicationController ctrl;
    if (Get.isRegistered<CommunicationController>()) {
      ctrl = CommunicationController.instance;
      ctrl.sessionId.value = session.id; // Ensure sessionId is set
      ctrl.sessionType.value =
          CommunicationSessionType.call; // [FIX]: Ensure sessionType is set
      ctrl.sessionName.value = session.isVideo
          ? 'Video Call'
          : 'Audio Call'; // Ensure sessionName is set
      ctrl.statusRx.value =
          CommSessionStatus.ringingIncoming; // Ensure status is set
    } else {
      ctrl = Get.put(CommunicationController(), permanent: true);
      ctrl.sessionId.value = session.id;
      ctrl.sessionType.value =
          CommunicationSessionType.call; // [FIX]: Ensure sessionType is set
      ctrl.sessionName.value = session.isVideo ? 'Video Call' : 'Audio Call';
      ctrl.statusRx.value = CommSessionStatus.ringingIncoming;
    }

    // Handover to Sovereign Controller for Prepare & Bind
    await ctrl.acceptCall();
  }

  void onCallConnected() {
    _callStartTime = DateTime.now();
  }

  void onCallEndedManually(String sessionId) {
    if (currentSession.value?.id == sessionId) {
      _logMetrics(sessionId, CallStatus.ended);
      currentSession.value = null;
      callStatus.value = CallStatus.ended;
    }
  }

  void _logMetrics(String sessionId, CallStatus status) {
    final now = DateTime.now();
    final duration =
        _callStartTime != null ? now.difference(_callStartTime!).inSeconds : 0;

    debugPrint(
        'CALL_METRICS: { id: $sessionId, duration: $duration, status: ${status.name} }');
    _callStartTime = null;
  }

  /// [SAFETY_GUARD]: Helper to ensure navigation only happens when the navigator is ready.
  Future<void> _safeNavigate(String route,
      {dynamic arguments, bool isOff = false}) async {
    final bool isGetXReady = Get.key.currentState != null;

    if (_isAppReady && isGetXReady) {
      // [SAFETY_GUARD]: Prevent duplicate navigation pushes
      if (Get.currentRoute == route) return;

      if (isOff) {
        unawaited(Get.offNamed(route, arguments: arguments));
      } else {
        unawaited(Get.toNamed(route, arguments: arguments));
      }
    } else {
      debugPrint(
          '📞 CallManager: Deferring navigation to $route (Ready: $_isAppReady, Context: $isGetXReady).');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeNavigate(route, arguments: arguments, isOff: isOff);
      });
    }
  }
}
