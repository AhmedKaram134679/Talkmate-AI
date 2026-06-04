import '../../trust_ethics/gate/trust_decision_gate.dart';
import '../models/decision_trace.dart';

/// Calculates how confident the system is in a decision (0.0 - 1.0).
class DecisionConfidenceIndex {
  static double calculate(DecisionTrace trace) {
    double score = 1.0;

    // Penalty for Risk
    score -= (trace.riskLevel * 0.5); // Higher risk reduces confidence

    // Penalty for Disagreement (Overrides)
    if (trace.reason.contains('Override') || trace.reason.contains('Veto')) {
      score -= 0.2; // Internal conflict
    }

    // Penalty for low Trust if Allowed
    if (trace.finalDecision == GateDecision.allow && trace.trustScore < 50) {
      score -= 0.1;
    }

    return score.clamp(0.0, 1.0);
  }
}
