import 'package:talkmate_ai/core/app_brain/feature_negotiation/models/negotiation_result.dart';
import 'package:talkmate_ai/core/app_brain/self_awareness/models/decision_trace.dart';

/// The result of a feature requesting access to resources/action.
class AssimilationResult {
  final bool isAllowed;
  final NegotiationDecision decision; // Approve, Degrade, Delay, Reject
  final Map<String, dynamic> constraints;
  final DecisionTrace? trace;
  final String reason;

  AssimilationResult({
    required this.isAllowed,
    required this.decision,
    required this.constraints,
    this.trace,
    this.reason = '',
  });

  factory AssimilationResult.blocked(String reason, {DecisionTrace? trace}) {
    return AssimilationResult(
      isAllowed: false,
      decision: NegotiationDecision.reject,
      constraints: {'enabled': false},
      trace: trace,
      reason: reason,
    );
  }
}
