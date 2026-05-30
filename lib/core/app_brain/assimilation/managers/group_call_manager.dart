import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../adaptive/adaptive_controller.dart';
import '../../adaptive/adaptive_models.dart';
import '../engine/call_quality_optimizer.dart';
import '../feature_assimilation_layer.dart';
import '../models/call_decision_context.dart';
import '../models/call_session_model.dart';
import '../models/participant_call_profile.dart';

/// Manages active call sessions and integrates with the Brain for intelligence.
class GroupCallManager extends GetxService {
  final Map<String, CallSession> _activeSessions = {};

  /// Starts a new session or joins an existing one.
  Future<CallSession?> requestSession(
      String featureId, String sessionId, List<String> participantIds) async {
    debugPrint(
        '📞 GroupCallManager: Requesting session $sessionId for $participantIds');

    final assimilation = Get.find<FeatureAssimilationLayer>();

    // 1. Initial Brain Access for the feature itself
    final result =
        assimilation.requestAccess(featureId, action: 'start_call', context: {
      'session_id': sessionId,
      'participant_count': participantIds.length,
    });

    if (!result.isAllowed) {
      debugPrint('🛑 GroupCall: Session BLOCKED by Brain: ${result.reason}');
      return null;
    }

    // 2. Create Session
    final session = CallSession(
      sessionId: sessionId,
      participants: participantIds
          .map((id) => ParticipantCallProfile(participantId: id))
          .toList(),
    );

    // 3. Optimize each participant based on Brain constraints and real resource context
    final adaptive = AdaptiveController.instance;
    final latestSignals = adaptive.latestSignals;

    final resourceContext = CallDecisionContext(
      networkQuality: latestSignals[AdaptiveSignalType.jitter]?.value ?? 0.8,
      batteryLevel: latestSignals[AdaptiveSignalType.battery]?.value ?? 0.9,
      concurrentCalls: participantIds.length,
    );

    for (var participant in session.participants) {
      CallQualityOptimizer.optimize(participant, result, resourceContext);
    }

    _activeSessions[sessionId] = session;
    return session;
  }

  /// Dynamically updates quality for a session based on changing resource conditions.
  void refreshSessionQuality(String sessionId, CallDecisionContext context) {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    debugPrint(
        '🔄 Refreshing quality for session $sessionId based on resources...');

    final assimilation = Get.find<FeatureAssimilationLayer>();
    // Re-check Brain for any new constraints (e.g. Battery Low might trigger new policy)
    final result = assimilation.requestAccess('calls_v1',
        action: 'adapt_to_resource_change');

    for (var participant in session.participants) {
      CallQualityOptimizer.optimize(participant, result, context);
    }
  }

  void endSession(String sessionId) {
    _activeSessions.remove(sessionId);
    debugPrint('📞 Session $sessionId ended.');
  }

  CallSession? getSession(String sessionId) => _activeSessions[sessionId];
}
