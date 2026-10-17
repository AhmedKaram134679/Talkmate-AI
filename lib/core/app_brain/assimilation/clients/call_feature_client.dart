import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/feature_assimilation_layer.dart';
import 'package:talkmate_ai/core/app_brain/self_reflection/models/decision_outcome.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/core/release/feature_flag_provider.dart';
import 'package:talkmate_ai/core/release/release_models.dart';
import 'package:talkmate_ai/data/models/call_model.dart' as data;
import 'package:talkmate_ai/services/call/call_governance_skeleton.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';
import 'package:talkmate_ai/services/call/video_infrastructure_manager.dart';
import 'package:talkmate_ai/services/call/voice_infrastructure_manager.dart';
import 'package:talkmate_ai/services/observability/app_observability.dart';

import '../../adaptive/adaptive_controller.dart';
import '../../adaptive/adaptive_models.dart';
import '../../app_events.dart';
import '../engine/accountability_engine.dart';
import '../engine/ai_moderation_manager.dart';
import '../engine/audio_presence_controller.dart';
import '../engine/av_stability_controller.dart';
import '../engine/compliance_manager.dart';
import '../engine/enterprise_integration_manager.dart';
import '../engine/enterprise_sovereignty_manager.dart';
import '../engine/global_scaling_manager.dart';
import '../engine/group_call_session_controller.dart';
import '../engine/human_sovereign_symbiosis_engine.dart';
import '../engine/media_hardening_manager.dart';
import '../engine/production_readiness_manager.dart';
import '../engine/regulatory_compliance_manager.dart';
import '../engine/room_capability_engine.dart';
import '../engine/room_recording_manager.dart';
import '../engine/self_governance_engine.dart';
import '../engine/session_authority_manager.dart';
import '../engine/session_intelligence_engine.dart';
import '../engine/session_legitimacy_manager.dart';
import '../engine/silent_ai_moderator_engine.dart';
import '../engine/sovereign_analytics_manager.dart';
import '../engine/sovereign_communication_engine.dart';
import '../engine/sovereign_ethical_identity_engine.dart';
import '../managers/group_call_manager.dart';
import '../models/ai_moderation_models.dart';
import '../models/audio_presence_models.dart';
import '../models/av_stability_models.dart';
import '../models/call_decision_context.dart';
import '../models/call_session_model.dart';
import '../models/global_expansion_models.dart';
import '../models/group_call_models.dart';
import '../models/human_sovereign_symbiosis_models.dart';
import '../models/legal_compliance_models.dart';
import '../models/participant_call_profile.dart';
import '../models/production_readiness_models.dart';
import '../models/recording_models.dart';
import '../models/room_capability_models.dart';
import '../models/secure_media_models.dart';
import '../models/self_governance_models.dart';
import '../models/session_identity_models.dart';
import '../models/session_sovereignty_models.dart';
import '../models/sovereign_analytics_models.dart';

/// Intelligent Client for Calls.
/// Intercepts requests and translates Brain commands into GroupCallManager actions.
class CallFeatureClient extends GetxService
    implements IMultimediaSystemGovernance {
  final _intelligence = Get.put(SessionIntelligenceEngine());
  final _authority = Get.put(SessionAuthorityManager());
  final _legitimacy = Get.put(SessionLegitimacyManager());
  final _silentAi = Get.put(SilentAICoModeratorEngine());
  final _accountability = Get.put(InstitutionalAccountabilityEngine());
  final _compliance = Get.put(ComplianceProfileManager());
  final _enterpriseManager = Get.put(EnterpriseSovereigntyManager());
  final _legalManager = Get.put(RegulatoryComplianceManager());
  final _voiceInfrastructure = Get.put(VoiceInfrastructureManager());
  final _videoInfrastructure = Get.put(VideoInfrastructureManager());
  final _stability = Get.put(AVStabilityController());
  final _hardening = Get.put(MediaSessionHardeningManager());
  final _audioPresence = Get.put(AudioPresenceController());
  final _capabilities = Get.put(RoomCapabilityEngine());
  final _commEngine = Get.put(SovereignCommunicationEngine());
  final _groupSession = Get.put(GroupCallSessionController());
  final _recording = Get.put(RoomRecordingManager());
  final _aiModeration = Get.put(AIModerationManager());
  final _production = Get.put(ProductionReadinessManager());
  final _scaling = Get.put(GlobalScalingManager());
  final _enterprise = Get.put(EnterpriseIntegrationManager());
  final _analytics = Get.put(SovereignAnalyticsManager());
  final _governance = Get.put(SelfGovernanceEngine());
  final _symbiosis = Get.put(HumanSovereignSymbiosisEngine());
  final _ethics = Get.put(SovereignEthicalIdentityEngine());

  @override
  String get featureId => 'multimedia_system_v1';

  @override
  bool get isHealthy => true;

  @override
  bool get isIsolated => true;

  @override
  bool get isSignalingReady => _currentSession != null;

  final _groupManager = Get.put(GroupCallManager());
  CallSession? _currentSession;
  Timer? _metricsTimer;

  @override
  bool get supportsVideo {
    // Stage E6: Video enabled if flag is active and system is healthy
    final flags = Get.find<FeatureFlagProvider>();
    return flags.getFeatureState('video_calls_v1') == FeatureState.enabled &&
        AdaptiveController.instance.currentLevel != PerformanceLevel.critical;
  }

  @override
  bool get allowHighBitrate =>
      _currentSession?.participants
          .any((p) => p.quality == CallQuality.highVideo) ??
      false;

  @override
  Future<void> boot() async {
    debugPrint('MultimediaExecutionManager: Constitutional Boot up...');
    await _voiceInfrastructure.initialize();
    await _videoInfrastructure.initialize();

    // Stage G4-Secure: Monitor cryptographic/identity health
    ever(_hardening.currentState.obs, (state) {
      if (state == MediaSecureState.terminated) {
        debugPrint(
            '🛡️ SECURITY BREACH or JWT EXPIRY: Triggering Automatic Hard Kill.');
        hardKill();
      }
    });

    // Stage G6: Audio Presence Constitution Logic
    ever(_audioPresence.speakingQueue.obs, (queue) {
      // Automatic arbitration could happen here
      if (queue.isNotEmpty &&
          _audioPresence.getState('currentUser') ==
              AudioPresenceState.requestingToSpeak) {
        // Mocking automatic grant for demo
        _audioPresence.grantSpeakingPower('currentUser');
      }
    });

    // Binding Audio State to Hardware Voice Loop
    ever(_audioPresence.getState('currentUser').obs, (state) async {
      if (state == AudioPresenceState.mutedSelf ||
          state == AudioPresenceState.mutedSystem) {
        await _voiceInfrastructure.deactivateVoice();
      } else if (state == AudioPresenceState.speaking) {
        await _voiceInfrastructure.activateVoice();
      }
    });

    // Stage G7: Individual Quality & Capability Routing
    ever<VideoResolution>(_capabilities.preferredResolution.obs,
        (resolution) async {
      debugPrint(
          '📉 CallClient: Adjusting hardware pipeline to ${resolution.name}');
      // Logic to update encoder bitrate/resolution would go here
    });

    ever<Set<RoomCapability>>(_capabilities.activeCapabilities.obs,
        (caps) async {
      if (!caps.contains(RoomCapability.video)) {
        await _videoInfrastructure.deactivateCamera();
      }
      if (!caps.contains(RoomCapability.screenShare)) {
        // Logic to stop screen share pipeline
      }
    });

    // Stage G9: AI Moderation Watchdog
    ever(_aiModeration.state.obs, (state) {
      if (state == AIModerationState.terminated) {
        debugPrint(
            '🛑 AIModeration: SYSTEM TERMINATED BY BRAIN. Hard Killing.');
        hardKill();
      }
    });

    // Stage G10: Production Readiness Watchdogs
    ever(_production.healthState.obs, (state) {
      if (state == SystemHealthState.critical) {
        debugPrint('🚨 PRODUCTION CRITICAL: Global Shutdown Triggered.');
        hardKill();
      }
    });

    ever(_production.activeKillSwitches.obs, (switches) async {
      if (switches.contains(FeatureKillSwitch.video)) {
        await _videoInfrastructure.deactivateCamera();
      }
      if (switches.contains(FeatureKillSwitch.audio)) {
        await _voiceInfrastructure.deactivateVoice();
      }
    });

    // Stage G14: Autonomous Self-Governance Watchdog
    ever(_governance.decisionStream.obs, (decision) async {
      final d = decision as AutonomousDecisionLog?;
      if (d == null) return;

      // Stage G16: Ethical Validation (The Moral Filter)
      if (!_ethics.evaluateEthicalStanding(d)) {
        debugPrint(
            '🕊️ ETHICAL VETO: Decision ${d.type.name} BLOCKED by Moral Conscience.');
        return;
      }

      debugPrint(
          '🏛️ GOVERNANCE EXECUTION: Applying ${d.type.name} [Rationale: ${d.rationale}]');

      // Stage G15: Explain to Human Symbiosis
      _symbiosis.pushSystemDecision(d);

      if (d.type == SovereignDecisionType.securityHardKill &&
          d.appliedConstraints['force_kill'] == true) {
        await hardKill();
      } else if (d.type == SovereignDecisionType.qualityAdjustment) {
        await applyPolicy(d.appliedConstraints);
      }
    });

    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  @override
  void handleGlobalEvent(AppBrainEvent event) {
    // Stage E5 / B2: Monitor emergency signals
    if (event is SystemEvent && event.type == 'emergency_start') {
      final action = event.metadata['action']?.toString();
      final reason = event.metadata['value']?.toString() ?? '';
      
      // [Stage B2]: Protect ongoing calls from non-multimedia emergency stops (e.g. sync failure).
      // Only trigger hardKill if the emergency explicitly requires terminating media or security breach.
      if (action == 'terminate_media' || reason.toLowerCase().contains('security_breach')) {
        debugPrint('🚨 [CallFeatureClient] Critical security/media emergency: triggering hardKill.');
        hardKill();
      } else {
        debugPrint('🛡️ [CallFeatureClient] Non-fatal emergency signal received ($reason). Preserving active call lifecycle.');
      }
    }
  }

  @override
  Future<void> hardKill() async {
    debugPrint('🛑 MULTIMEDIA HARD KILL ACTIVATED! Purging all resources...');

    _metricsTimer?.cancel();
    _metricsTimer = null;

    // 0. Audio & Video Infrastructure Hard Kill (Stage G1 & G2)
    await _voiceInfrastructure.audioHardKill();
    await _videoInfrastructure.videoHardKill();

    // 0.1 Stage G4-Secure: Release Security Locks
    _hardening.releaseSession();

    // 0.2 Stage G5: Terminate Group Room
    _groupSession.killRoom();

    // 0.3 Stage G6: Audio Presence Hard Kill
    _audioPresence.audioHardKill('currentUser');

    // 0.4 Stage G8: Recording Hard Kill
    _recording.recordingHardKill();

    // 0.5 Stage G9: AI Moderation Hard Kill
    _aiModeration.moderationHardKill('currentUser');

    // 0.6 Stage G10: Global Production Hard Kill
    _production.globalHardKill();

    // 0.7 Stage G12: Enterprise Integration Hard Kill
    _enterprise.integrationHardKill(null);

    // 0.8 Stage G13: Analytics Hard Kill
    _analytics.analyticsHardKill();

    // 0.9 Unified Comm Hard Cleanup (C3)
    await _commEngine.endSession('currentUser');

    // 1. Terminate actual executing engine
    await CallManager.instance.terminateCall(status: data.CallStatus.rejected);

    // 2. Clear legitimacy, AI and governance session
    if (_currentSession != null) {
      final sessionId = _currentSession!.sessionId;

      // Stage F6: Emergency Accountability Log
      _accountability.logSovereignDecision(
        sessionId: sessionId,
        action: SovereignAction.terminateSession,
        authority: 'EmergencySystemAuthority',
        technicalBasis: 'Hard Kill Protocol Triggered',
        policyReference: 'TM_SOV_EMERGENCY_01',
      );

      if (_compliance.isEvidencePackRequired()) {
        _accountability.generateEvidencePack(
            sessionId, _compliance.currentProfile.value);

        // Stage F8: Legal Evidence Sealing
        final interpretation = _legalManager.interpretDecision(
            SovereignAction.terminateSession,
            'Emergency Hard Kill',
            RegulatoryFramework.gdpr);
        _legalManager.sealEvidencePack(sessionId, [interpretation]);
      }

      if (_compliance.getArchiveRetentionHours() == 0) {
        _silentAi.purgeSessionAiData(sessionId);
        _legitimacy.purgeSessionSovereignty(sessionId);
        _accountability.purgeAccountabilityData(sessionId);
        _enterpriseManager.purgeEnterpriseContext(sessionId);
        _legalManager.purgeLegalContext(sessionId);
      }

      _groupManager.endSession(sessionId);
      _currentSession = null;
    }
  }

  @override
  Future<void> applyPolicy(Map<String, dynamic> constraints) async {
    debugPrint('CallFeatureClient: Applying policy $constraints');
    // In multi-party, individual quality is managed via Manager.
    // This method handles global overrides.
    if (constraints['enabled'] == false || constraints['force_kill'] == true) {
      await hardKill();
    }
  }

  /// Request to start/join a group call.
  Future<bool> startCall(String sessionId, List<String> participantIds,
      {String orgId = 'default_org', bool activateMedia = true}) async {
    debugPrint('📞 CallClient: Requesting P2P/Group Call $sessionId...');

    // 0. Enterprise Sovereignty Check (Stage F7)
    final context =
        _enterpriseManager.initializeSessionContext(orgId, sessionId);
    if (context == null) {
      debugPrint('🛑 CallClient: UNKNOWN Enterprise Context for $orgId');
      return false;
    }

    // Unified Comm Lock (Stage C3)
    final locked = await _commEngine.requestSessionLock(
        sessionId, CommunicationSessionType.call);
    if (!locked) return false;

    // Identity & Legitimacy Registration (Stage F4)
    final participant = await _legitimacy.validateAndRegister(
        sessionId, 'currentUser', SessionRole.host, JoinContext.invite);

    if (participant == null) {
      debugPrint('🛑 CallClient: Session entry REJECTED by Legitimacy Gate.');
      await _commEngine.endSession('currentUser');
      return false;
    }

    // Gatekeeper Check via GroupManager's requestSession
    _currentSession = await _groupManager.requestSession(
        featureId, sessionId, participantIds);

    if (_currentSession == null) {
      return false;
    }

    debugPrint(
        '✅ Call SESSION REGISTERED (Muted/Controlled): $_currentSession');

    // 2. Stage G5: Join Sovereign Group Voice Room
    final joined = await _groupSession.joinRoom(
      sessionId,
      'currentUser', // Mocked user identity
      'User Display Name',
      participantIds.length > 1
          ? ParticipantRole.moderator
          : ParticipantRole.host,
    );

    if (!joined) {
      debugPrint('🛑 CallClient: GROUP SESSION BINDING FAILED.');
      await hardKill();
      return false;
    }

    if (activateMedia && participantIds.length > 1) {
      // 3. Activate Sovereign Protection ONLY for Rooms/Group calls immediately.
      // Standard 1v1 calls wait for P2P connection success in CommunicationController.
      await _commEngine.activateProtection('currentUser');

      // 4. Activate Hardware Audio Path (Stage G1)
      await _voiceInfrastructure.activateVoice();
    }

    // 4. Stage G9: Start Intelligent AI Analysis
    await _aiModeration.startAnalysis('currentUser');

    // 5. Stage G11: Global Node Negotiation
    final node = _scaling.negotiateBestNode(GlobalRegion.meSouth);
    if (node != null) {
      debugPrint(
          '🌍 GlobalScaling: Routing session to NODE ${node.nodeId} [${node.ipAddress}]');
      // In real scenario, we would pass this IP to SessionAuthorityManager
    }

    return true;
  }

  /// Process a live signal from the session and trigger necessary governance actions.
  Future<void> processIntelligenceSignal(
      IntelligenceSignalType type, double value) async {
    if (_currentSession == null) return;

    final sessionId = _currentSession!.sessionId;

    // 1. Traditional Governance Escalation (Stage F3)
    final escalation = _intelligence.analyzeSignal(sessionId, type, value);

    if (escalation != EscalationLevel.none) {
      await _authority.handleEscalation(sessionId, escalation);
    }

    // 2. Silent AI Advisor (Stage F5)
    final recommendation =
        _silentAi.analyzeAndRecommend(sessionId, type, value);
    if (recommendation != null) {
      // Human-in-the-Loop: Pass to Authority for evaluation
      await _authority.handleAiRecommendation(recommendation);
    }
  }

  /// Manually enforce a sovereign action via the authority engine (G15 Symbiosis).
  Future<bool> enforceAuthorityAction(SovereignAction action,
      {String? targetUserId, String? reason}) async {
    if (_currentSession == null) return false;

    // Stage G16: Ethical Conscience Check
    if (!_ethics.shouldExecute(
        action.name, {'target': targetUserId, 'reason': reason})) {
      debugPrint('🕊️ CallClient: Action REJECTED by Ethical Identity Engine.');
      return false;
    }

    // Stage G15: Symbiotic Verification of Human Authority
    final status = _symbiosis.evaluateHumanCommand(
        action.name, {'target': targetUserId, 'reason': reason});

    if (status == HumanCommandStatus.rejected) {
      debugPrint(
          '🛑 CallClient: Action REJECTED by Symbiosis Engine (Constitution Veto).');
      return false;
    }

    return await _authority.executeAction(_currentSession!.sessionId, action,
        targetUserId: targetUserId, reason: reason);
  }

  /// Toggle local camera (Stage G2)
  Future<void> toggleVideo(bool enable) async {
    if (_currentSession == null) return;
    if (enable) {
      await _videoInfrastructure.activateCamera();
    } else {
      await _videoInfrastructure.deactivateCamera();
    }
  }

  /// Start recording the current room (Stage G8).
  Future<bool> startRoomRecording(Set<RecordingTrackType> tracks) async {
    if (_currentSession == null) return false;
    return await _recording.startRecording(_currentSession!.sessionId, tracks);
  }

  /// Stop current room recording.
  Future<void> stopRoomRecording() async {
    await _recording.stopRecording();
  }

  /// Pause/Resume toggle for recording.
  void toggleRecordingPause() {
    if (_recording.currentRecording?.state == RecordingState.paused) {
      _recording.resumeRecording();
    } else {
      _recording.pauseRecording();
    }
  }

  /// Toggle local audio mute (Stage G6 Sovereign Mute).
  Future<void> toggleAudioMute(bool mute) async {
    if (_currentSession == null) return;

    // Stage G6: User's decision is absolute
    _audioPresence.applyMute(
        'currentUser', mute ? MuteType.self : MuteType.hostReq);

    if (mute) {
      await _voiceInfrastructure.deactivateVoice();
    } else {
      await requestSpeakingSlot();
    }
  }

  /// Request a slot in the speaking queue (Stage G6 Priority).
  Future<void> requestSpeakingSlot() async {
    if (_currentSession == null) return;
    await _audioPresence.requestToSpeak('currentUser');
  }

  /// Simulate a resource change during call
  void simulateResourceShift(double network, double battery) {
    if (_currentSession == null) return;

    // 1. Log quality metrics (Observability)
    final observability = Get.find<AppObservability>();
    observability.logCallQualityMetrics(
        _currentSession!.sessionId, network, battery);

    // 2. Feed Intelligence Engine (Stage F3)
    processIntelligenceSignal(IntelligenceSignalType.audioLevel, 45.0); // Mock
    processIntelligenceSignal(IntelligenceSignalType.packetLoss, 1.0 - network);

    // Stage G13: Push Granular Data for Proactive Analytics
    _analytics.pushDataPoint(SovereignDataPoint(
      type: AnalyticsMetricType.packetLoss,
      value: 1.0 - network,
      timestamp: DateTime.now(),
    ));

    // 3. Stage G3: AV Stability Engine Analysis
    final metrics = AVQualityMetrics(
      rttMs: (500 * (1.0 - network)).toInt(),
      packetLoss: 1.0 - network,
      jitterMs: 20.0 * (1.0 - network),
      fps: 30,
    );

    final decision = _stability.analyzeStability(metrics);
    _applyStabilityDecision(decision);

    final context = CallDecisionContext(
        networkQuality: network,
        batteryLevel: battery,
        concurrentCalls: _currentSession!.participants.length);

    _groupManager.refreshSessionQuality(_currentSession!.sessionId, context);
  }

  /// Locally apply the stability decision (Stage G3).
  void _applyStabilityDecision(StabilityDecision decision) {
    switch (decision) {
      case StabilityDecision.maintain:
        debugPrint('🧘 AVStability: System Stable.');
        break;
      case StabilityDecision.degradeResolution:
        debugPrint(
            '📉 AVStability: Reducing resolution due to unstable network.');
        degradeQuality(lowBitrate: true);
        break;
      case StabilityDecision.throttleFrameRate:
        debugPrint('🎞️ AVStability: Throttling frame rate.');
        break;
      case StabilityDecision.lowerBitrate:
        debugPrint('🎧 AVStability: Forcing low bitrate.');
        degradeQuality(lowBitrate: true);
        break;
      case StabilityDecision.audioOnly:
        debugPrint(
            '🔇 AVStability: Network critical. Dropping video for voice priority.');
        degradeQuality(videoOff: true);
        break;
      case StabilityDecision.terminate:
        debugPrint('🛑 AVStability: Network fatal. Emergency termination.');
        hardKill();
        break;
    }
  }

  /// Called when call ends
  Future<void> endCall(bool userTerminated, double qualityRating) async {
    if (_currentSession == null) return;

    debugPrint('📞 Call Ended. Generating Health Report...');

    final sessionId = _currentSession!.sessionId;

    // Generate Final Health Report (Stage F3)
    final report = _intelligence.generateHealthReport(
        sessionId,
        const Duration(minutes: 5), // Mock
        qualityRating);
    debugPrint('📊 Final Session Health: ${report.stabilityScore}');

    // Stage G13: Generate Final Sovereign Analytics Report
    await _analytics.generateFinalReport(
        sessionId, DateTime.now().subtract(const Duration(minutes: 5)));

    // 3. Institutional Accountability (Stage F6)
    if (_compliance.isEvidencePackRequired()) {
      _accountability.generateEvidencePack(
          sessionId, _compliance.currentProfile.value);
      debugPrint('💼 Compliance: Evidence Pack generated for auditing.');

      // Stage F8: Legal Evidence Sealing & Interpretation
      final interpretation = _legalManager.interpretDecision(
          SovereignAction.terminateSession, // Mocking final session lock
          'Session Lifecycle Complete',
          RegulatoryFramework.gdpr);
      _legalManager.sealEvidencePack(sessionId, [interpretation]);
    }

    // 4. Data Retention & Privacy Compliance
    if (_compliance.getArchiveRetentionHours() == 0) {
      _silentAi.purgeSessionAiData(sessionId);
      _legitimacy.purgeSessionSovereignty(sessionId);
      _accountability.purgeAccountabilityData(sessionId);
      _enterpriseManager.purgeEnterpriseContext(sessionId);
      _legalManager.purgeLegalContext(sessionId);
    } else {
      debugPrint(
          '🏛️ Compliance: Archiving metadata for ${_compliance.getArchiveRetentionHours()}h as per policy.');
    }

    final assimilation = Get.find<FeatureAssimilationLayer>();
    assimilation.reportOutcome(
        featureId,
        userTerminated ? OutcomeStatus.success : OutcomeStatus.failure,
        qualityRating);

    _groupManager.endSession(_currentSession!.sessionId);

    // 5. Release Hardware Audio & Video Path (Stage G1 & G2)
    await _voiceInfrastructure.deactivateVoice();
    await _videoInfrastructure.deactivateCamera();

    // 6. Stage G4-Secure: Release Security Locks
    _hardening.releaseSession();

    // 7. Stage G5: Leave Group Room
    await _groupSession.leaveRoom('currentUser');

    // 8. Unified Comm Release (C3)
    await _commEngine.endSession('currentUser');

    _currentSession = null;
  }

  @override
  Future<void> degradeQuality(
      {bool videoOff = false, bool lowBitrate = false}) async {
    if (_currentSession == null) {
      return;
    }

    final sessionId = _currentSession!.sessionId;
    final enterpriseContext = _enterpriseManager.getContext(sessionId);
    final profile = enterpriseContext?.adaptiveProfile;

    debugPrint('📉 VoiceClient: Adaptive degradation active.');

    // Manually force all participants to low quality for simulation
    for (var p in _currentSession!.participants) {
      if (videoOff) {
        p.quality = CallQuality.audioOnly;
      } else if (lowBitrate && p.quality == CallQuality.highVideo) {
        // Respect enterprise profile if available
        if (profile != null && !profile.allowHighVideo) {
          p.quality = CallQuality.audioOnly;
        } else {
          p.quality = CallQuality.lowVideo;
        }
      }
    }
  }

  @override
  void onClose() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
    super.onClose();
  }
}
