import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../adaptive/adaptive_controller.dart';
import '../../adaptive/adaptive_models.dart';
import '../engine/accountability_engine.dart';
import '../feature_gatekeeper.dart';
import '../models/ai_sovereignty_models.dart';
import '../models/session_sovereignty_models.dart';

/// Session Authority Engine.
/// Responsible for executing sovereign actions within a live session.
class SessionAuthorityManager extends GetxService {
  final _gatekeeper = Get.find<FeatureGatekeeper>();

  /// Executes a sovereign action if permitted by the Governance Gate.
  Future<bool> executeAction(String sessionId, SovereignAction action,
      {String? targetUserId, String? reason}) async {
    debugPrint(
        '⚖️ SessionAuthority: Requesting $action for $sessionId | Reason: $reason');

    // 1. Governance Validation
    final response =
        _gatekeeper.requestAccess('multimedia_system_v1', action: action.name);

    if (!response.isAllowed) {
      debugPrint('🛑 SessionAuthority: Action BLOCKED: ${response.reason}');
      return false;
    }

    // 2. Adaptive Policy Check
    if (AdaptiveController.instance.currentLevel == PerformanceLevel.critical &&
        (action == SovereignAction.unmute ||
            action == SovereignAction.allowVideo)) {
      debugPrint(
          '🛑 SessionAuthority: Restoration blocked due to CRITICAL system state.');
      return false;
    }

    // 3. Execution (Simulated for F3)
    debugPrint('✅ SessionAuthority: EXECUTING $action on $sessionId');

    // Log intervention for the health report
    _logIntervention(sessionId, action, reason ?? 'System Decision');

    return true;
  }

  void _logIntervention(
      String sessionId, SovereignAction action, String reason) {
    // Stage F6: Constitutional Accountability
    final accountability = Get.find<InstitutionalAccountabilityEngine>();
    accountability.logSovereignDecision(
      sessionId: sessionId,
      action: action,
      authority: 'SystemAuthority', // In F6, we track the triggering entity
      technicalBasis: reason,
      policyReference: 'TM_SOV_POL_01', // Governance Policy Template
    );

    debugPrint('📝 Intervention Logged & Audited: $action for $reason');
  }

  /// Handles a recommendation from the Silent AI (Human-in-the-Loop).
  Future<bool> handleAiRecommendation(
      AiSovereignRecommendation recommendation) async {
    debugPrint(
        '🤖 SessionAuthority: Evaluating AI Recommendation ${recommendation.recommendationId}');

    if (recommendation.isExpired) {
      debugPrint('🛑 SessionAuthority: Recommendation EXPIRED.');
      return false;
    }

    // 1. Contextual Trust Check (F4 Compliance)
    // For high risk, we might require specific host approval (Mocked here)
    if (recommendation.risk == RecommendationRisk.high ||
        recommendation.risk == RecommendationRisk.critical) {
      debugPrint(
          '⚠️ SessionAuthority: HIGH RISK detected. Awaiting Host/System override...');
    }

    // 2. Execution through established Sovereign Gate
    final success = await executeAction(
        recommendation.sessionId, recommendation.actionSuggested,
        reason: 'AI Advisory: ${recommendation.technicalJustification}');

    recommendation.isHandled = true;
    return success;
  }

  /// Handles an escalation triggered by the Intelligence Layer.
  Future<void> handleEscalation(String sessionId, EscalationLevel level) async {
    switch (level) {
      case EscalationLevel.alert:
        debugPrint('🧠 Escalation: SOFT ALERT issued for $sessionId');
        break;
      case EscalationLevel.intervention:
        debugPrint('🧠 Escalation: INTERVENTION active. Muting noisy session.');
        await executeAction(sessionId, SovereignAction.mute,
            reason: 'Auto-Intervention: Noise Detected');
        break;
      case EscalationLevel.hardKill:
        debugPrint('🧠 Escalation: HARD KILL triggered for $sessionId');
        await executeAction(sessionId, SovereignAction.terminateSession,
            reason: 'Critical System Protection');
        break;
      default:
        break;
    }
  }
}
