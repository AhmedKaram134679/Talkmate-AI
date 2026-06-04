import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';

/// [Stage R30]: Strict WebRTC Lifecycle States
enum CallState {
  idle,
  initializing,
  negotiating,
  connected,
  mediaFlowing,
  answering,
  disposing,
  closed
}

/// [Stage R30]: Persistent Peer Container for State Hardening
class SovereignPeer {
  final webrtc.RTCPeerConnection pc;
  final String userId;
  bool hasLocalSdp = false;
  bool hasRemoteSdp = false;
  bool negotiationLock = false;
  bool isInitializing = false;
  final List<webrtc.RTCIceCandidate> iceQueue = [];
  final Set<String> processedTrackIds = {};
  CallState state = CallState.idle;
  bool isDisposed = false;
  DateTime? iceConnectedAt; // [Area 2]: DTLS Watchdog start time
  bool signalingFrozen = false; // [Deterministic] Hard lock after Answer
  bool hasAnswered = false; // [Idempotency] Zero duplicate writes
  bool isIceEmissionStopped = false; // [Governance] Controlled emission

  // [R34] Perfect Negotiation State
  bool makingOffer = false;
  bool isSettingRemoteAnswerPending = false;
  // Note: isPolite is managed by CommunicationController but used here for logic

  SovereignPeer(this.pc, this.userId);

  void transition(CallState newState) {
    debugPrint(
        '🧭 [R30] State Transition ($userId): ${state.name} → ${newState.name}');
    state = newState;
  }

  /// [Area 1]: Explicitly reset flags for new negotiation cycles
  void resetSdpFlags() {
    debugPrint('🚩 [Area 1] SDP Flags Reset ($userId)');
    hasLocalSdp = false;
    hasRemoteSdp = false;
  }

  /// [R30] Native Call Protection Guard
  bool _pcGuard(String callName) {
    if (isDisposed) {
      debugPrint(
          '🚫 [R30] Event Ignored - Disposed State ($userId: $callName)');
      return false;
    }
    // Unified check for disposed or closed state
    if (pc.signalingState == webrtc.RTCSignalingState.RTCSignalingStateClosed) {
      debugPrint(
          '⚠️ [R30] Native Call Blocked - Invalid PC State (Closed Signaling) ($userId: $callName)');
      return false;
    }

    return true;
  }

  /// [R30] Atomic Negotiation Lock
  Future<webrtc.RTCSessionDescription> createOffer(
      [Map<String, dynamic>? constraints]) async {
    if (!_pcGuard('createOffer')) throw Exception('Invalid PC State');

    debugPrint('🔄 [R30] Negotiation Locked ($userId)');
    resetSdpFlags(); // [Area 1]: Reset version-scoped flags on new offer
    negotiationLock = true;
    transition(CallState.negotiating);

    try {
      return await pc.createOffer(constraints ?? {});
    } finally {
      // Lock remains until setLocal + setRemote are stable
    }
  }

  Future<void> setLocalDescription(
      webrtc.RTCSessionDescription description) async {
    if (!_pcGuard('setLocalDescription')) return;
    await pc.setLocalDescription(description);
    hasLocalSdp = true;

    // [R30] Unlock after Answer if state is now stable and we have both descriptions
    if (pc.signalingState == webrtc.RTCSignalingState.RTCSignalingStateStable &&
        hasRemoteSdp) {
      _unlockNegotiation();
    }
  }

  Future<void> setRemoteDescription(
      webrtc.RTCSessionDescription description) async {
    if (!_pcGuard('setRemoteDescription')) return;
    if (signalingFrozen) {
      debugPrint('🛡️ [R30] Signaling FROZEN - Remote SDP Ignored ($userId)');
      return;
    }
    await pc.setRemoteDescription(description);
    hasRemoteSdp = true;

    // If state is now stable and we have local sdp, unlock
    if (pc.signalingState == webrtc.RTCSignalingState.RTCSignalingStateStable &&
        hasLocalSdp) {
      _unlockNegotiation();
    }
  }

  bool get isStable =>
      pc.signalingState == webrtc.RTCSignalingState.RTCSignalingStateStable;

  /// [R30] Native Guarded createAnswer
  Future<webrtc.RTCSessionDescription> createAnswer(
      [Map<String, dynamic>? constraints]) async {
    if (!_pcGuard('createAnswer')) throw Exception('PeerConnection is NULL');

    debugPrint('🔄 [R30] Negotiation Locked (Answer) ($userId)');
    negotiationLock = true;
    transition(CallState.answering);

    try {
      return await pc.createAnswer(constraints ?? {});
    } catch (e) {
      _unlockNegotiation();
      rethrow;
    }
  }

  void _unlockNegotiation() {
    if (!negotiationLock) return;
    if (pc.signalingState != webrtc.RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('⚠️ [R30] Unlock Deferred - PC Not Stable ($userId)');
      return;
    }

    debugPrint('🔓 [R30] Negotiation Unlocked ($userId)');
    negotiationLock = false;
    transition(CallState.connected);
    _drainIceQueue();
  }

  /// [R30] ICE Staging Queue (Enterprise Guard Area 1)
  Future<void> addCandidate(webrtc.RTCIceCandidate candidate) async {
    if (!_pcGuard('addCandidate')) return;

    // [Area 1]: Strict Gating - Require BOTH remote and local description completion
    // This prevents silent ICE breakage on Windows which occurs if candidates
    // arrive before the PC has a full context of the session (both SDPs).
    if (!hasRemoteSdp || !hasLocalSdp || negotiationLock) {
      debugPrint(
          '📦 [R30] ICE Candidate Buffered ($userId) (Local: $hasLocalSdp, Remote: $hasRemoteSdp, Locked: $negotiationLock)');
      iceQueue.add(candidate);
      return;
    }

    try {
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('⚠️ [R30] ICE Add Failed (Safe Skip): $e');
    }
  }

  Future<void> _drainIceQueue() async {
    if (isDisposed || iceQueue.isEmpty) return;

    // Safety double-check for drain
    if (!hasLocalSdp || !hasRemoteSdp) return;

    debugPrint(
        '🚰 [R30] ICE Queue Drained ($userId: ${iceQueue.length} items)');
    final candidates = List<webrtc.RTCIceCandidate>.from(iceQueue);
    iceQueue.clear();

    for (var c in candidates) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('⚠️ [R30] ICE Drain Error (Skipping): $e');
      }
    }
  }

  // Dispose Fence
  Future<void> dispose() async {
    if (isDisposed) return;
    debugPrint('🛑 [R30] Dispose Fence Activated ($userId)');
    isDisposed = true;
    state = CallState.disposing;

    iceQueue.clear();
    try {
      await pc.close();
      await pc.dispose();
    } catch (e) {
      debugPrint('⚠️ [R30] Dispose error: $e');
    }
    state = CallState.closed;
  }

  // Expose necessary getters for legacy compatibility
  webrtc.RTCIceConnectionState? get iceConnectionState => pc.iceConnectionState;
  Future<List<webrtc.RTCRtpSender>> getSenders() => pc.getSenders();
  Future<List<webrtc.RTCRtpReceiver>> getReceivers() => pc.getReceivers();
  Future<List<webrtc.StatsReport>> getStats() => pc.getStats();
  Future<webrtc.RTCSessionDescription?> getRemoteDescription() =>
      pc.getRemoteDescription();

  Future<void> setConfiguration(Map<String, dynamic> configuration) async {
    if (!_pcGuard('setConfiguration')) return;
    await pc.setConfiguration(configuration);
  }

  Future<webrtc.RTCSessionDescription> restartIce() async {
    if (!_pcGuard('restartIce')) throw Exception('Invalid PC State');
    return await createOffer({'iceRestart': true});
  }

  Future<void> addTrack(webrtc.MediaStreamTrack track,
      [webrtc.MediaStream? stream]) async {
    if (!_pcGuard('addTrack')) return;
    if (stream != null) {
      await pc.addTrack(track, stream);
    } else {
      await pc.addTrack(track);
    }
  }

  Future<void> removeTrack(webrtc.RTCRtpSender sender) async {
    if (!_pcGuard('removeTrack')) return;
    await pc.removeTrack(sender);
  }

  /// [Carrier-Grade] Area 6: Dynamic Bitrate Control
  Future<void> setBitrate(int kbps) async {
    if (!_pcGuard('setBitrate')) return;
    final senders = await pc.getSenders();
    for (var sender in senders) {
      if (sender.track?.kind == 'audio') {
        final parameters = sender.parameters;
        if (parameters.encodings != null && parameters.encodings!.isNotEmpty) {
          for (var encoding in parameters.encodings!) {
            encoding.maxBitrate = kbps * 1000;
          }
          await sender.setParameters(parameters);
          debugPrint(
              '📉 [Carrier-Grade] Area 6: Bitrate limited to ${kbps}kbps ($userId)');
        }
      }
    }
  }

  Future<webrtc.RTCRtpTransceiver> addTransceiver({
    webrtc.RTCRtpMediaType? kind,
    webrtc.MediaStreamTrack? track,
    webrtc.RTCRtpTransceiverInit? init,
  }) async {
    if (!_pcGuard('addTransceiver')) throw Exception('Invalid PC State');
    if (kind != null) {
      return await pc.addTransceiver(
          kind: kind, init: init ?? webrtc.RTCRtpTransceiverInit());
    } else if (track != null) {
      return await pc.addTransceiver(
          track: track, init: init ?? webrtc.RTCRtpTransceiverInit());
    } else {
      throw Exception(
          'Either kind or track must be provided to addTransceiver');
    }
  }

  Future<List<webrtc.RTCRtpTransceiver>> getTransceivers() async {
    if (!_pcGuard('getTransceivers')) return [];
    return await pc.getTransceivers();
  }

  set onIceCandidate(Function(webrtc.RTCIceCandidate?)? callback) =>
      pc.onIceCandidate = callback;
  set onTrack(Function(webrtc.RTCTrackEvent)? callback) =>
      pc.onTrack = callback;
  set onConnectionState(Function(webrtc.RTCPeerConnectionState)? callback) =>
      pc.onConnectionState = callback;
  set onIceConnectionState(Function(webrtc.RTCIceConnectionState)? callback) =>
      pc.onIceConnectionState = callback;
  set onSignalingState(Function(webrtc.RTCSignalingState)? callback) =>
      pc.onSignalingState = callback;

  Future<void> dumpForensicDetails() async {
    debugPrint('[R31][WINDOWS_AUDIO_FLOW] --- START FOR $userId ---');
    try {
      final senders = await pc.getSenders();
      final receivers = await pc.getReceivers();
      final transceivers = await pc.getTransceivers();

      for (var s in senders) {
        final t = s.track;
        if (t != null) {
          debugPrint(
              '  [SENDER] kind=${t.kind}, id=${t.id}, enabled=${t.enabled}');
        }
      }
      for (var r in receivers) {
        final t = r.track;
        if (t != null) {
          debugPrint(
              '  [RECEIVER] kind=${t.kind}, id=${t.id}, enabled=${t.enabled}');
        }
      }
      for (var tr in transceivers) {
        debugPrint('  [TRANSCEIVER] mid=${tr.mid}');
      }

      final local = await pc.getLocalDescription();
      final remote = await pc.getRemoteDescription();
      debugPrint('  [SDP] Local: ${local?.type}, Remote: ${remote?.type}');
      if (local != null) {
        final lines = local.sdp?.split('\n') ?? [];
        final mLines = lines.where((l) => l.startsWith('m=')).toList();
        debugPrint('  [SDP] Local m-lines: ${mLines.length} -> $mLines');
        debugPrint('  [SDP] Local Audio/Video Count: '
            'A=${lines.where((l) => l.contains('m=audio')).length}, '
            'V=${lines.where((l) => l.contains('m=video')).length}');
      }
      // [NEW] Android Diagnostic Phase (R32 Preparation)
      if (GetPlatform.isAndroid) {
        debugPrint('[R31][ANDROID_DIAGNOSTIC] Starting sender trace...');
        for (var s in senders) {
          debugPrint('ANDROID SENDER TRACK: ${s.track?.kind} '
              'enabled=${s.track?.enabled}');
        }

        // [R32] PART 1 — SELECTED PAIR FORENSIC EXTRACTION
        try {
          final stats = await pc.getStats();
          Map<dynamic, dynamic>? selectedPair;
          Map<dynamic, dynamic>? localCandidate;
          Map<dynamic, dynamic>? remoteCandidate;

          for (var report in stats) {
            if (report.type == 'candidate-pair' &&
                report.values['selected'] == true) {
              selectedPair = report.values;
            }
          }

          if (selectedPair != null) {
            final localId = selectedPair['localCandidateId'];
            final remoteId = selectedPair['remoteCandidateId'];

            for (var report in stats) {
              if (report.id == localId) localCandidate = report.values;
              if (report.id == remoteId) remoteCandidate = report.values;
            }

            final localType = localCandidate?['candidateType'] ?? 'unknown';
            final remoteType = remoteCandidate?['candidateType'] ?? 'unknown';

            debugPrint('[R32][ICE_SELECTED_PAIR]');
            debugPrint('localCandidateType=$localType');
            debugPrint('remoteCandidateType=$remoteType');
            debugPrint('candidatePairState=${selectedPair['state']}');
            debugPrint('priority=${selectedPair['priority']}');
          } else {
            debugPrint('[R32][ICE_SELECTED_PAIR] NONE_FOUND');
          }

          for (var report in stats) {
            if (report.type == 'outbound-rtp' &&
                report.values['kind'] == 'audio') {
              final bytesSent = report.values['bytesSent'];
              debugPrint(
                  '  [R32][STATS] bytesSent (audio outbound): $bytesSent');
            }
            if (report.type == 'media-source' &&
                report.values['kind'] == 'audio') {
              final audioLevel = report.values['audioLevel'];
              debugPrint('  [R32][STATS] audioLevel: $audioLevel');
            }
          }
        } catch (e) {
          debugPrint('  [R32][STATS_ERROR] Failed to get stats: $e');
        }
      }

      // [AEC_DIAGNOSTIC]: Windows Acoustic Echo Cancellation Stats
      if (GetPlatform.isWindows) {
        debugPrint('[R32][WINDOWS_AEC_DIAGNOSTIC] Starting stats trace...');
        final aecStats = await checkAECStats();
        debugPrint(
            '  [AEC] ERL (Echo Return Loss): ${aecStats['echoReturnLoss']}');
        debugPrint(
            '  [AEC] ERLE (Enhancement): ${aecStats['echoReturnLossEnhancement']}');

        if ((aecStats['echoReturnLoss'] ?? 0) < -0.5) {
          debugPrint(
              '  ⚠️ [AEC] ERL is negative/invalid! AEC might not be active.');
        }
      }
    } catch (e) {
      debugPrint('  [R32][FORENSIC_ERROR] Failed to dump details: $e');
    }
    debugPrint('[R32][DIAGNOSTIC] --- END ---');
  }

  /// [ADVISORY_SYSTEM]: Monitor AEC Effectiveness (ERL/ERLE)
  Future<Map<String, double>> checkAECStats() async {
    final Map<String, double> aecStats = {
      'echoReturnLoss': -1.0,
      'echoReturnLossEnhancement': -1.0,
    };

    try {
      final reports = await pc.getStats();
      for (var report in reports) {
        if (report.type == 'media-source' && report.values['kind'] == 'audio') {
          final erl = report.values['echoReturnLoss'];
          final erle = report.values['echoReturnLossEnhancement'];

          if (erl != null) {
            aecStats['echoReturnLoss'] =
                double.tryParse(erl.toString()) ?? -1.0;
          }
          if (erle != null) {
            aecStats['echoReturnLossEnhancement'] =
                double.tryParse(erle.toString()) ?? -1.0;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AEC_DIAG] Failed to get AEC stats: $e');
    }

    return aecStats;
  }

  Future<void> close() => pc.close();
}

/// [Stage R3]: Sovereign WebRTC Connection Manager
/// Responsible for lifecycle of RTCPeerConnections and MediaStreams.
class WebRTCConnectionManager {
  static final WebRTCConnectionManager instance =
      WebRTCConnectionManager._internal();

  // Peer mapping: userId -> SovereignPeer
  final Map<String, SovereignPeer> _peers = {};

  Iterable<String> get allPeerIds => _peers.keys;

  // [Stage R7]: ICE Candidate Buffering (Legacy - moving to SovereignPeer)
  final Map<String, List<webrtc.RTCIceCandidate>> _pendingCandidates = {};

  // Local Stream
  webrtc.MediaStream? localStream;

  bool _isDisposing = false; // Guard for atomic disposal

  // [Stage R23]: ICE Watchdog Management
  final Map<String, Timer?> _iceWatchdogs = {};
  static const Duration _iceWatchdogTimeout = Duration(seconds: 8);

  /// [Area 3]: ICE Failure Watchdog
  Function(String userId, String reason)? onIceFailure;

  /// [Area 7]: Hardware Device Change Watchdog
  Function()? onDeviceChange;

  void addLog(String message) {
    debugPrint(message);
  }

  WebRTCConnectionManager._internal() {
    webrtc.navigator.mediaDevices.ondevicechange = (event) {
      debugPrint('🔌 [Area 7] Native Device Change detected.');
      onDeviceChange?.call();
    };
  }

  // ICE Configuration
  // ICE Configuration
  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    // [ICE_REFINEMENT]: Configurable policy (Default: all, Test: relay)
    'iceTransportPolicy': 'all',
  };

  Map<String, dynamic> get iceConfig => _iceConfig;

  // [REPAIR P2]: Legacy OfferToReceiveAudio/OfferToReceiveVideo removed.
  // Under Unified Plan, media directions are controlled exclusively by the
  // explicit SendRecv transceivers created in initPeerConnection(). Keeping the
  // legacy receive flags here caused libwebrtc to synthesize extra recvonly
  // m-lines on top of the transceivers (duplicate/contradictory audio sections).
  final Map<String, dynamic> _constraints = {
    'mandatory': {},
    'optional': [],
    'sdpSemantics': 'unified-plan', // Ensure modern WebRTC behavior
  };

  /// Forces the ICE transport policy (e.g., 'relay' for critical tests)
  void setIceTransportPolicy(String policy) {
    _iceConfig['iceTransportPolicy'] = policy;
    addLog('🧊 ICE: Policy shifted to $policy');
  }

  /// [Carrier-Grade] Area 1: Dynamic Update for ICE Servers (TURN Refresh)
  Future<void> setIceServers(List<Map<String, dynamic>> servers) async {
    _iceConfig['iceServers'] = servers;
    addLog(
        '🧊 [Area 1] ICE Servers updated in config (Count: ${servers.length})');

    // Proactively apply to all active peers
    for (var peer in _peers.values) {
      if (!peer.isDisposed) {
        try {
          await peer.pc.setConfiguration(_iceConfig);
          addLog(
              '✅ [Area 1] Applied fresh TURN config to peer: ${peer.userId}');
        } catch (e) {
          addLog(
              '⚠️ [Area 1] Failed to apply fresh config to ${peer.userId}: $e');
        }
      }
    }
  }

  Future<SovereignPeer> initPeerConnection(
    String remoteUserId, {
    required Function(webrtc.MediaStream stream) onStreamAdded,
    required Function(webrtc.RTCIceCandidate candidate) onIceCandidate,
    Function(webrtc.RTCIceConnectionState state)? onIceStateChanged,
    bool isVideo = false,
  }) async {
    // [R30] Re-entrancy Protection
    if (_peers[remoteUserId]?.isInitializing == true) {
      debugPrint('⚠️ [R30] Re-entrant Init Blocked ($remoteUserId)');
      return _peers[remoteUserId]!;
    }

    // [REPAIR P2]: No longer inject OfferToReceiveVideo. Receive direction is
    // guaranteed by the SendRecv transceivers added below.
    final customConstraints = Map<String, dynamic>.from(_constraints);

    final pc = await webrtc.createPeerConnection(_iceConfig, customConstraints);
    final peer = SovereignPeer(pc, remoteUserId);
    peer.isInitializing = true;
    peer.transition(CallState.initializing);
    _peers[remoteUserId] = peer;

    // [R30] Single Authority for Audio/Video Setup (Windows Hardening)
    if (GetPlatform.isWindows && localStream != null) {
      addLog(
          '🔒 [R30] Media Authority Locked ($remoteUserId) (isVideo: $isVideo)');

      // [R30/R33] Unified Media Authority (Single m-line Enforcement)
      for (var track in localStream!.getTracks()) {
        try {
          await peer.pc.addTransceiver(
            track: track,
            init: webrtc.RTCRtpTransceiverInit(
              direction: webrtc.TransceiverDirection.SendRecv,
              streams: [localStream!],
            ),
          );
          addLog(
              '🔒 [R33] Track Bound & Transceiver Created: ${track.id} (${track.kind})');
        } catch (e) {
          addLog('⚠️ [R33] Track Bind Error: $e');
        }
      }
    } else if (!GetPlatform.isWindows && localStream != null) {
      // [REPAIR P1]: Android/non-Windows path now uses SendRecv (was SendOnly).
      // SendOnly made Android declare sendonly m-lines, so the peer answered
      // recvonly and the reverse media direction was never negotiated, causing
      // one-way audio/video on Android<->Android and Android<->Windows.
      for (var track in localStream!.getTracks()) {
        await peer.addTransceiver(
          track: track,
          init: webrtc.RTCRtpTransceiverInit(
            direction: webrtc.TransceiverDirection.SendRecv,
            streams: [localStream!],
          ),
        );
      }
    }

    peer.onTrack = (event) async {
      final track = event.track;

      // [AUDIO_DEDUPLICATION]: Prevent double binding/playback if onTrack fires twice
      if (peer.processedTrackIds.contains(track.id)) {
        debugPrint(
            '🛡️ [R32] onTrack ignored (Duplicate Track ID: ${track.id})');
        return;
      }
      peer.processedTrackIds.add(track.id!);

      // [AUDIO_FIX]: Explicitly enable remote track
      track.enabled = true;
      try {
        event.receiver?.track?.enabled = true;
      } catch (_) {}

      if (track.kind == 'audio' && !track.enabled) {
        track.enabled = true;
        debugPrint('🎧 SHIELD: Audio track force-enabled (OEM/EdgeCase)');
      }

      debugPrint('[ANDROID] onTrack fired: ${track.kind}');
      // [Step 3 Diagnostic]: Verify remote track reception
      debugPrint('📥 onTrack fired: kind=${track.kind}');
      // [MANDATORY_DIAGNOSTIC]: Per User Request
      debugPrint('🎧 Audio track id=${track.id}, enabled=${track.enabled}');

      if (track.kind == 'audio') {
        debugPrint('🔊 Remote audio track received & enabled=${track.enabled}');
        if (GetPlatform.isWindows) {
          debugPrint('🪟 Windows: [AUDIO_ISOLATION] Remote track verified.');
        }
      }

      // [Stage R25]: Robust Stream Handling
      // If streams is empty, we MUST create a fallback stream to ensure the renderer gets the track.
      webrtc.MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams[0];
      } else {
        debugPrint(
            '⚠️ onTrack: Empty streams for ${track.kind}. Creating fallback.');
        try {
          stream = await webrtc
              .createLocalMediaStream('remote_fallback_${track.id}');
          // [SAFETY]: Verify track is still valid and wrap in try-catch to prevent native crash
          if (track.kind != null) {
            await stream.addTrack(track);
          }
        } catch (e) {
          debugPrint('⚠️ onTrack: Fallback addTrack failed: $e');
          return; // Abort this track processing
        }
      }

      // [ANDROID_ROUTING]: Ensure all tracks in stream are enabled
      stream.getAudioTracks().forEach((t) {
        t.enabled = true;
        debugPrint('🎧 Stream Track Force-Enabled: ${t.id}');
      });

      debugPrint('🎧 onTrack: ${track.kind} (Explicitly ENABLED)');

      // [NATIVE_AUDIO_HARDENING]: Professional PCM Sink Handover - DISABLED
      // Default WebRTC Audio Output used instead.
      onStreamAdded(stream);
    };

    pc.onConnectionState = (state) {
      debugPrint('⚡ WebRTC: Peer $remoteUserId state: $state');
      if (state ==
          webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Transitional disconnected state
      } else if (state ==
          webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // [STABILITY_FIX]: Do NOT remove peer immediately.
        // Let CommunicationController handle recovery or cleanup.
        debugPrint(
            '⚠️ WebRTC: Peer $remoteUserId FAILED. Waiting for recovery logic...');
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('🧊 WebRTC: Peer $remoteUserId ICE state: $state');
      _handleIceStateChange(remoteUserId, state);
      onIceStateChanged?.call(state);
    };

    peer.onIceCandidate = (candidate) {
      // [Stage R23]: Proactive Watchdog Trigger: If we are generating local candidates,
      // the connection SHOULD move to connected soon.
      _startIceWatchdog(remoteUserId, 'Local Candidate Generated');

      // [R31][ICE_FORENSICS] Candidate Type Detection
      if (candidate != null) {
        final cStr = candidate.candidate ?? '';
        String type = 'unknown';
        if (cStr.contains(' typ host ')) {
          type = 'host';
        } else if (cStr.contains(' typ srflx ')) {
          type = 'srflx';
        } else if (cStr.contains(' typ relay ')) {
          type = 'relay';
        }

        debugPrint(
            '🧊 [ICE_FORENSICS] Local Candidate ($remoteUserId): type=$type, mid=${candidate.sdpMid}, index=${candidate.sdpMLineIndex}');
        onIceCandidate(candidate);
      }
    };

    _peers[remoteUserId] = peer;
    peer.isInitializing = false;
    return peer;
  }

  /// [Stage R25]: Create Restart Offer (ICE Restart)
  /// Forces a new ICE gathering process for the peer.
  Future<webrtc.RTCSessionDescription> createRestartOffer(String userId) async {
    final peer = _peers[userId];
    if (peer == null) throw Exception('Peer $userId not found');

    final Map<String, dynamic> constraints = Map.from(_constraints);
    constraints['optional'] ??= [];
    constraints['mandatory'] ??= {};
    constraints['mandatory']['IceRestart'] = true;

    final offer = await peer.createOffer(constraints);
    await peer.setLocalDescription(offer);
    return offer;
  }

  SovereignPeer? getSovereign(String userId) => _peers[userId];

  webrtc.RTCPeerConnection? getPeer(String userId) => _peers[userId]?.pc;

  /// [Carrier-Grade]: Access to the persistent container for watchdogs and drift monitoring
  SovereignPeer? getSovereignPeer(String userId) => _peers[userId];

  /// [Stage R23]: ICE Watchdog Logic
  void _startIceWatchdog(String userId, String reason) {
    if (_iceWatchdogs[userId] != null) return; // Already running

    debugPrint('🛡️ [ICE_WATCHDOG] Started for $userId (Reason: $reason)');
    _iceWatchdogs[userId] = Timer(_iceWatchdogTimeout, () {
      final peer = _peers[userId];
      if (peer != null) {
        final rawState = peer.iceConnectionState;
        // [HARDENING]: Ensure we log the actual Enum string if .name is missing/null
        final String stateStr =
            rawState != null ? rawState.toString().split('.').last : 'null';

        if (rawState !=
                webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected &&
            rawState !=
                webrtc.RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          debugPrint(
              '🚨 [ICE_WATCHDOG] EXPIRED for $userId! State: $stateStr. Triggering failure callback.');
          onIceFailure?.call(userId, stateStr);
        }
      }
      _iceWatchdogs.remove(userId);
    });
  }

  void _stopIceWatchdog(String userId) {
    if (_iceWatchdogs.containsKey(userId)) {
      debugPrint('🛡️ [ICE_WATCHDOG] Stopped for $userId (Connection Healthy)');
      _iceWatchdogs[userId]?.cancel();
      _iceWatchdogs.remove(userId);
    }
  }

  void _handleIceStateChange(
      String userId, webrtc.RTCIceConnectionState state) {
    final peer = _peers[userId];
    debugPrint('🧊 Sovereign Stability: Peer $userId ICE state -> $state');
    if (state == webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == webrtc.RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      if (peer != null) {
        peer.iceConnectedAt ??= DateTime.now();
        debugPrint(
            '🧊 Sovereign Stability: Peer $userId ICE Connected at ${peer.iceConnectedAt}');
      }
      _stopIceWatchdog(userId);
    } else if (state ==
        webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _stopIceWatchdog(userId);
      onIceFailure?.call(userId, 'failed');
    }
  }

  /// [Stage R9]: Stats helper for audio levels (VU Meter)
  Future<double> getAudioLevel(String userId) async {
    final peer = _peers[userId];
    if (peer == null) return 0.0;

    try {
      final reports = await peer.getStats();
      for (var report in reports) {
        // Look for inbound-rtp or receiver stats that contain audioLevel
        if (report.type == 'inbound-rtp' || report.type == 'media-source') {
          final level = report.values['audioLevel'];
          if (level != null) {
            return (double.tryParse(level.toString()) ?? 0.0);
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting stats for $userId: $e');
    }
    return 0.0;
  }

  /// [Stage R28.2]: Get detailed RTP stats for diagnostics
  Future<List<webrtc.StatsReport>> getDetailedStats(String userId) async {
    final peer = _peers[userId];
    if (peer == null) return [];
    try {
      return await peer.getStats();
    } catch (e) {
      debugPrint('Error getting detailed stats for $userId: $e');
      return [];
    }
  }

  /// [Stage R28]: Get total bytes received for a peer
  Future<int> getBytesReceived(String userId) async {
    final peer = _peers[userId];
    if (peer == null) return 0;

    try {
      final reports = await peer.getStats();
      int totalBytes = 0;
      for (var report in reports) {
        if (report.type == 'inbound-rtp') {
          final bytes =
              int.tryParse(report.values['bytesReceived']?.toString() ?? '0') ??
                  0;
          totalBytes += bytes;
        }
      }
      return totalBytes;
    } catch (e) {
      debugPrint('Error getting bytesReceived for $userId: $e');
      return 0;
    }
  }

  /// [ADVISORY_SYSTEM]: Get current level of local audio track via OutboundRtp statistics
  Future<double> getLocalAudioLevel() async {
    if (localStream == null) return 0.0;
    final audioTrack = localStream!.getAudioTracks().firstOrNull;
    if (audioTrack == null) return 0.0;

    // [PRODUCTION_HARDENING]: Switch to RTCOutboundRtpStreamStats for accuracy.
    for (var pc in _peers.values.toList()) {
      try {
        final reports = await pc.getStats();
        for (var report in reports) {
          if (report.type == 'outbound-rtp' &&
              report.values['kind'] == 'audio') {
            final level = report.values['audioLevel'];
            if (level != null) {
              return (double.tryParse(level.toString()) ?? 0.0);
            }
          }
        }
      } catch (_) {}
    }
    return 0.0;
  }

  /// [Area 2]: AEC Diagnostic statistics for Windows
  /// Returns a map with 'ERL' (Echo Return Loss) and 'ERLE' (Echo Return Loss Enhancement) if available.
  Future<Map<String, double>> getAECStats() async {
    final Map<String, double> aecStats = {'ERL': 0.0, 'ERLE': 0.0};

    for (var peer in _peers.values) {
      if (peer.isDisposed) continue;
      try {
        final reports = await peer.pc.getStats();
        for (var report in reports) {
          // stats property names vary by libwebrtc version
          // media-source stats usually contain the most accurate AEC info
          if (report.type == 'media-source' &&
              report.values['kind'] == 'audio') {
            final erl = report.values['echoReturnLoss'];
            final erle = report.values['echoReturnLossEnhancement'];
            if (erl != null) {
              aecStats['ERL'] = double.tryParse(erl.toString()) ?? 0.0;
            }
            if (erle != null) {
              aecStats['ERLE'] = double.tryParse(erle.toString()) ?? 0.0;
            }
            if (aecStats['ERL']! > 0) return aecStats;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [AEC_DIAG] Peer stats failed: $e');
      }
    }
    return aecStats;
  }

  /// [Area 3]: Audit ICE statistics for Relay Enforcement
  Future<Map<String, dynamic>> getIceStats(String userId) async {
    final peer = _peers[userId];
    if (peer == null) return {'available': false};

    try {
      final reports = await peer.pc.getStats();
      for (var report in reports) {
        if (report.type == 'candidate-pair' &&
            (report.values['selected'] == true ||
                report.values['state'] == 'succeeded')) {
          final localId = report.values['localCandidateId'];
          final remoteId = report.values['remoteCandidateId'];
          final double rtt =
              (report.values['currentRoundTripTime'] ?? 0.0) as double;

          String localType = 'unknown';
          String remoteType = 'unknown';

          for (var r in reports) {
            if (r.id == localId) {
              localType = r.values['candidateType'] ?? 'unknown';
            }
            if (r.id == remoteId) {
              remoteType = r.values['candidateType'] ?? 'unknown';
            }
          }

          // [Area 2]: DTLS State Search
          String dtlsState = 'unknown';
          for (var r in reports) {
            if (r.type == 'transport') {
              dtlsState = r.values['dtlsState'] ?? 'unknown';
              break;
            }
          }

          // [Area 4]: Packet Loss Search (Inbound RTP)
          int packetsLost = 0;
          int packetsReceived = 0;
          for (var r in reports) {
            if (r.type == 'inbound-rtp' && r.values['kind'] == 'audio') {
              packetsLost = (r.values['packetsLost'] ?? 0) as int;
              packetsReceived = (r.values['packetsReceived'] ?? 0) as int;
              break;
            }
          }

          return {
            'localType': localType,
            'remoteType': remoteType,
            'isRelay': localType == 'relay' || remoteType == 'relay',
            'isHostToHost': localType == 'host' && remoteType == 'host',
            'dtlsState': dtlsState,
            'rtt': rtt,
            'packetsLost': packetsLost,
            'packetsReceived': packetsReceived,
            'available': true,
          };
        }
      }
    } catch (e) {
      debugPrint('⚠️ [ICE_AUDIT] Failed for $userId: $e');
    }
    return {'available': false};
  }

  /// [ADVISORY_SYSTEM]: Enumerate all audio input devices
  Future<List<webrtc.MediaDeviceInfo>> getAudioDevices() async {
    try {
      final devices = await webrtc.navigator.mediaDevices.enumerateDevices();
      return devices.where((d) => d.kind == 'audioinput').toList();
    } catch (e) {
      debugPrint('⚠️ WebRTC: Failed to enumerate devices: $e');
      return [];
    }
  }

  Future<void> removePeer(String userId) async {
    final pc = _peers[userId];
    if (pc != null) {
      _stopIceWatchdog(userId);
      await pc.dispose();
      _peers.remove(userId);
    }
    _pendingCandidates.remove(userId);
    _iceWatchdogs.remove(userId);
    debugPrint('🗑️ WebRTC: Peer $userId removed');
  }

  /// [Stage R2]: Initialize Local Media (Camera/Mic)
  Future<webrtc.MediaStream> initLocalMedia(
      {bool isAudio = true, bool isVideo = false}) async {
    // [HARDENING]: Explicitly stop existing tracks of the same kind before requesting new ones.
    // This is critical on Windows to prevent "Device in use" circular locks.
    if (localStream != null) {
      if (isAudio) {
        for (var t in localStream!.getAudioTracks()) {
          debugPrint('🛑 Stopping existing local audio track: ${t.id}');
          await t.stop();
        }
      }
      if (isVideo) {
        for (var t in localStream!.getVideoTracks()) {
          debugPrint('🛑 Stopping existing local video track: ${t.id}');
          await t.stop();
        }
      }
    }

    // [ARCHITECTURAL_DECISION]: Windows Audio Hardening
    // On Windows, some ADM implementations create a loopback if AGC or specific
    // processing is enabled, as it tries to monitor the output for cancellation reference.
    // We strictly disable these on Windows to force a "clean" capture path.
    final Map<String, dynamic> audioConstraints = GetPlatform.isWindows
        ? {
            'mandatory': {
              // [WINDOWS_AEC_HARDENING]: Enforcing AEC3 and pure capture
              'echoCancellation': true,
              'googEchoCancellation': true,
              'googEchoCancellation2': true,
              'googDAEchoCancellation': true,
              'googNoiseSuppression': true,
              'googNoiseSuppression2': true,
              'googHighpassFilter': true,
              'googTypingNoiseDetection': true,
              'googAutoGainControl':
                  false, // [CRITICAL]: AGC often interferes with AEC3 reference
              'sampleRate': 48000,
              'channelCount': 1,
              'voiceActivityDetection': false,
            },
            'optional': [],
          }
        : {
            // Android/iOS Defaults
            'mandatory': {
              'googEchoCancellation': true,
              'googEchoCancellation2': true,
              'googNoiseSuppression': true, // Keep enabled for now on Android
              'googNoiseSuppression2': true,
              'googAutoGainControl': true,
              'googHighpassFilter': true,
              'googTypingNoiseDetection': true,
              // [Stage R28.2]: Forensic Mode - Disable Silence Suppression
              'voiceActivityDetection': false,
            },
            'optional': [
              {'echoCancellation': true},
              {'googNoiseSuppression': true},
            ],
          };

    final Map<String, dynamic> mediaConstraints = {
      'audio': isAudio ? audioConstraints : false,
      'video': isVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      debugPrint(
          '🎙️ WebRTC: Requesting UserMedia with constraints: $mediaConstraints');
      final stream =
          await webrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      debugPrint('✅ WebRTC: UserMedia Granted (Stream ID: ${stream.id})');

      // [Stage R25]: Intelligent Stream Merging
      // If we already have a stream and we only requested one type, merge the tracks.
      if (localStream != null) {
        if (isAudio && !isVideo) {
          // Replace audio tracks
          final oldTracks = localStream!.getAudioTracks().toList();
          for (var t in oldTracks) {
            try {
              await localStream!.removeTrack(t);
            } catch (e) {
              debugPrint('⚠️ WebRTC: Failed to remove audio track: $e');
            }
          }
          for (var t in stream.getAudioTracks()) {
            await localStream!.addTrack(t);
          }
        } else if (isVideo && !isAudio) {
          // Replace video tracks
          final oldTracks = localStream!.getVideoTracks().toList();
          for (var t in oldTracks) {
            try {
              await localStream!.removeTrack(t);
            } catch (e) {
              debugPrint('⚠️ WebRTC: Failed to remove video track: $e');
            }
          }
          for (var t in stream.getVideoTracks()) {
            await localStream!.addTrack(t);
          }
        } else {
          // Full replacement
          localStream = stream;
        }
      } else {
        localStream = stream;
      }

      // [Step 2 Diagnostic]: Confirm Tracks are enabled
      localStream!.getAudioTracks().forEach((track) {
        track.enabled = true;
        debugPrint(
            '[AUDIO] Local track active: ${track.id} (Ready: ${track.enabled})');
      });

      localStream!.getVideoTracks().forEach((track) {
        track.enabled = true;
        debugPrint(
            '[VIDEO] Local track active: ${track.id} (Ready: ${track.enabled})');
      });

      return localStream!;
    } catch (e) {
      debugPrint('❌ Media Error (getUserMedia): $e');
      debugPrint('❌ Constraints that failed: $mediaConstraints');
      rethrow;
    }
  }

  /// [Stage R10]: Add local tracks to all existing peers (Transceiver Upgrade)
  Future<void> addLocalTracksToPeers() async {
    if (localStream == null) return;
    // [Stage R25]: Snapshot iteration for async track attachment
    for (var entry in _peers.entries.toList()) {
      final pc = entry.value;
      final transceivers = await pc.getTransceivers();
      final tracks = localStream!.getTracks();

      for (var track in tracks) {
        // [Stage R10.1]: Improved track reuse check
        // Check if track is already being sent by any transceiver
        final alreadySent = transceivers.any((t) =>
            t.sender.track?.id == track.id ||
            t.sender.track?.label == track.label);

        if (!alreadySent) {
          debugPrint(
              '🚀 WebRTC: Upgrading peer ${entry.key} with ${track.kind} transceiver');
          await pc.addTransceiver(
            track: track,
            init: webrtc.RTCRtpTransceiverInit(
              direction: webrtc.TransceiverDirection.SendRecv,
              streams: [localStream!],
            ),
          );
          // [WINDOWS_ROBUSTNESS]: Explicitly add track as well to trigger older driver hooks
          // Only apply on Windows to avoid IllegalStateException on Android/Web where transeivers are sufficient.
          if (GetPlatform.isWindows) {
            try {
              await pc.addTrack(track, localStream!);
            } catch (e) {
              // Might already be added via transceiver init, ignoring
              debugPrint('ℹ️ addTrack fallback info: $e');
            }
          }
          debugPrint(
              '[${track.kind?.toUpperCase()}] Track added to sender (Transceiver: sendrecv)');
        } else {
          debugPrint(
              'ℹ️ WebRTC: Track ${track.id} (${track.kind}) already present in peer ${entry.key}, skipping.');
        }
      }
    }
  }

  /// [REPAIR P5]: Attach the current local video track to every peer.
  ///
  /// Prefers `RTCRtpSender.replaceTrack()` when the peer already has a video
  /// sender (no new m-line, no renegotiation churn), and only creates a single
  /// `SendRecv` video transceiver when none exists yet. This never touches the
  /// audio sender, so mute/unmute stays in sync, and it cannot create the
  /// duplicate video m-lines that the previous add/remove-transceiver flow did.
  Future<void> upgradeVideoForPeers() async {
    final videoTrack = localStream?.getVideoTracks().firstOrNull;
    if (videoTrack == null) {
      debugPrint('⚠️ [P5] upgradeVideoForPeers: no local video track.');
      return;
    }
    for (var entry in _peers.entries.toList()) {
      final peer = entry.value;
      if (peer.isDisposed) continue;
      final pc = peer.pc;
      try {
        final senders = await pc.getSenders();
        webrtc.RTCRtpSender? videoSender;
        for (final s in senders) {
          if (s.track?.kind == 'video') {
            videoSender = s;
            break;
          }
        }
        if (videoSender != null) {
          await videoSender.replaceTrack(videoTrack);
          debugPrint(
              '🔁 [P5] Replaced video track on existing sender (${entry.key}).');
        } else {
          await pc.addTransceiver(
            track: videoTrack,
            init: webrtc.RTCRtpTransceiverInit(
              direction: webrtc.TransceiverDirection.SendRecv,
              streams: [localStream!],
            ),
          );
          debugPrint(
              '➕ [P5] Added SendRecv video transceiver (${entry.key}).');
        }
      } catch (e) {
        debugPrint('⚠️ [P5] upgradeVideoForPeers error (${entry.key}): $e');
      }
    }
  }

  void toggleAudio(bool isMuted) {
    debugPrint('🎙️ WebRTC: Toggling Audio -> Muted: $isMuted');
    localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
  }

  void toggleVideo(bool isVideoOn) {
    debugPrint('📹 WebRTC: Toggling Video -> On: $isVideoOn');
    localStream?.getVideoTracks().forEach((track) {
      track.enabled = isVideoOn;
    });
  }

  /// [ANDROID_ROUTING]: Explicitly toggle speakerphone and audio mode.
  Future<void> setSpeakerphoneOn(bool enabled) async {
    if (kIsWeb || !GetPlatform.isAndroid && !GetPlatform.isIOS) return;
    try {
      await webrtc.Helper.setSpeakerphoneOn(enabled);
      debugPrint('🔊 WebRTC: Speakerphone set to $enabled');
    } catch (e) {
      debugPrint('⚠️ WebRTC Speaker Error: $e');
    }
  }

  /// [ANDROID_ROUTING]: Force communication mode to avoid earpiece-only output.
  Future<void> setToCommunicationMode() async {
    if (kIsWeb || !GetPlatform.isAndroid) return;
    try {
      // [STEP 1 & 2]: Hardened Native Isolation
      // This blacklists internal WebRTC audio output and sets MODE_IN_COMMUNICATION
      await const MethodChannel('com.example.talkmate_ai/native_audio')
          .invokeMethod('prepareAudioIsolation');

      // [PRACTICAL_FIX]: Use user-suggested routing sequence for Android
      await webrtc.Helper.setSpeakerphoneOn(true);

      // [AUDIO_HARDENING]: Definitive Android Audio Configuration
      await webrtc.Helper.setAndroidAudioConfiguration(
        webrtc.AndroidAudioConfiguration(
          androidAudioMode: webrtc.AndroidAudioMode.inCommunication,
          androidAudioFocusMode: webrtc.AndroidAudioFocusMode.gain,
          manageAudioFocus: true,
        ),
      );

      // Default to speaker for TalkMate AI's room-based/messenger experience
      await webrtc.Helper.selectAudioOutput('speaker');

      debugPrint(
          '🔊 [ANDROID_HARDENING]: Audio routed to SPEAKER with Communication Mode');
    } catch (e) {
      debugPrint('⚠️ WebRTC Mode Error: $e');
    }
  }

  Future<void> switchCamera() async {
    if (localStream != null) {
      final videoTrack = localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await webrtc.Helper.switchCamera(videoTrack);
      }
    }
  }

  /// [Stage R5.5]: Real Volume Control
  Future<void> applyVolumeToReceiver(String trackId, double volume) async {
    // [Stage R25]: Snapshot iteration for async volume application
    for (var pc in _peers.values.toList()) {
      try {
        final receivers = await pc.getReceivers();
        for (var receiver in receivers) {
          if (receiver.track?.id == trackId) {
            // Placeholder: Most flutter_webrtc platforms don't have setVolume on receiver yet.
            // On desktop/mobile, this usually requires native audio session control.
            debugPrint('🔊 [WebRTC] Set Volume for $trackId to $volume');
            return;
          }
        }
      } catch (e) {
        debugPrint('Volume setup error: $e');
      }
    }
  }

  /// [Stage R7]: Handle incoming ICE candidate securely (buffer if needed)
  Future<void> addIncomingCandidate(
      String remoteUserId, webrtc.RTCIceCandidate candidate) async {
    final pc = _peers[remoteUserId];
    if (pc == null) return;

    // [PRODUCTION_GUARD]: Strictly buffer candidates until SDP negotiation is complete.
    // For Answerer: need RemoteOffer + LocalAnswer (SignalingState.Stable)
    // For Initiator: need LocalOffer + RemoteAnswer (SignalingState.Stable)
    final signalingState = pc.pc.signalingState;
    final bool isSafe =
        signalingState == webrtc.RTCSignalingState.RTCSignalingStateStable;

    if (isSafe) {
      // Safe to add
      await pc.addCandidate(candidate);
    } else {
      // Buffer it
      debugPrint(
          '🧊 ICE: Buffering candidate for $remoteUserId (SignalingState: $signalingState)');
      _pendingCandidates.putIfAbsent(remoteUserId, () => []).add(candidate);
    }
  }

  /// [Stage R7]: Drain buffered candidates after SetRemoteDescription
  Future<void> drainCandidates(String remoteUserId) async {
    final pc = _peers[remoteUserId];
    final candidates = _pendingCandidates[remoteUserId];
    if (pc == null || candidates == null || candidates.isEmpty) return;

    debugPrint(
        '🧊 ICE: Draining ${candidates.length} candidates for $remoteUserId');
    for (var c in candidates) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('⚠️ ICE: Drain candidate error (skipping): $e');
      }
    }
    _pendingCandidates.remove(remoteUserId);
  }

  /// [Stage R25]: Clear all buffered candidates (used during ICE Restart)
  void clearCandidates(String remoteUserId) {
    _pendingCandidates.remove(remoteUserId);
    debugPrint('🧊 ICE: Clearing old candidates for $remoteUserId');
  }

  /// Clean disposal of all media (Async to prevent main thread lock)
  Future<void> dispose() async {
    if (_isDisposing) {
      debugPrint('⚠️ WebRTC: Disposal already in progress, skipping.');
      return;
    }
    _isDisposing = true;

    debugPrint('🧹 WebRTC: Starting Sovereign Disposal...');

    // 1. Stop local tracks immediately to kill hardware indicator
    if (localStream != null) {
      final tracks = localStream!.getTracks();
      for (var track in tracks) {
        try {
          debugPrint('🛑 Stopping track: ${track.kind} (${track.id})');
          track.enabled = false;
          await track.stop();
        } catch (e) {
          debugPrint('⚠️ Track stop error: $e');
        }
      }
      debugPrint('[CLEANUP] All local tracks stopped');
      await localStream!.dispose();
      localStream = null;
    }

    // 2. Yield to UI thread to allow camera indicator to update on system
    await Future.delayed(const Duration(milliseconds: 100));

    // 3. Close peers sequentially with snapshot to prevent modification errors
    final peerIds = _peers.keys.toList();
    for (var userId in peerIds) {
      final pc = _peers[userId];
      if (pc != null) {
        try {
          // Remove all transceivers/senders to kill hardware binding
          final senders = await pc.getSenders();
          for (var sender in senders) {
            try {
              if (sender.track != null) {
                // 1. Stop track
                sender.track!.enabled = false;
                await sender.track!.stop();
                // 2. Remove Track (if supported by platform/pc)
                try {
                  await pc.removeTrack(sender);
                } catch (_) {}
              }
            } catch (_) {}
          }

          pc.onIceCandidate = null;
          pc.onTrack = null;
          pc.onConnectionState = null;
          pc.onIceConnectionState = null;
          pc.onSignalingState = null;

          await pc.close();
          await pc.dispose();
          debugPrint('[CLEANUP] PeerConnection closed & disposed');
        } catch (e) {
          debugPrint('⚠️ WebRTC: Error closing peer $userId: $e');
        }
      }
      // Allow main thread to breathe
      await Future.delayed(Duration.zero);
    }

    _peers.clear();
    _pendingCandidates.clear();
    for (var timer in _iceWatchdogs.values) {
      timer?.cancel();
    }
    _iceWatchdogs.clear();
    _isDisposing = false;
    debugPrint('✅ WebRTC: All hardware resources disposed (Sovereign).');
  }
}
