import '../../self_awareness/metrics/decision_confidence_index.dart';
import '../models/decision_outcome.dart';

/// Calculates "Cognitive Regret" - how much the system wishes it hadn't done that.
class RegretIndex {
  static double calculate(DecisionOutcome outcome) {
    // 1. Get Confidence at time of decision
    final confidence = DecisionConfidenceIndex.calculate(outcome.trace);

    // 2. Calculate Outcome Delta (1.0 = Perfect, 0.0 = Disaster)
    // If status is Rejected, Satisfaction is explicitly 0.
    double actualResultScore = outcome.satisfactionScore;
    if (outcome.status == OutcomeStatus.rejectedByUser) {
      actualResultScore = 0.0;
    }

    // 3. Regret Formula
    // Regret is high if we were CONFIDENT but FAILED.
    // Regret = Confidence * (1 - Result)

    double regret = confidence * (1.0 - actualResultScore);

    // Boost Regret if it was an Override (we broke a rule and failed)
    if (outcome.trace.reason.contains('Override')) {
      regret *= 1.2;
    }

    return regret.clamp(0.0, 1.0);
  }
}
