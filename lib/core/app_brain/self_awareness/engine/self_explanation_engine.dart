import '../../trust_ethics/gate/trust_decision_gate.dart';
import '../models/decision_trace.dart';

/// Converts mechanical decision traces into human-readable explanations.
class SelfExplanationEngine {
  String explain(DecisionTrace trace) {
    final decision = trace.finalDecision;
    final risk = trace.riskLevel;

    switch (decision) {
      case GateDecision.allow:
        if (trace.reason.contains('Personality Override')) {
          return 'I allowed this because my ${trace.personality.name} personality encourages taking risks (Level $risk), despite low trust.';
        }
        return 'Allowed normally based on sufficient trust and alignment.';

      case GateDecision.blockTrust:
        if (trace.reason.contains('Personality Veto')) {
          return 'Blocked because my ${trace.personality.name} personality is cautious about risk level $risk.';
        }
        return 'Blocked due to insufficient trust score (${trace.trustScore}).';

      case GateDecision.blockEthical:
        return 'Blocked immediately because it violates ethical boundaries.';
    }
  }
}
