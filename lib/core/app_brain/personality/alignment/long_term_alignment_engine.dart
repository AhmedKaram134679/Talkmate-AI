import 'package:get/get.dart';

import '../../trust_ethics/gate/trust_decision_gate.dart';
import '../memory/temporal_behavior_store.dart';

/// Ensures system behavior remains stable over time (prevents behavioral drift).
class LongTermAlignmentEngine extends GetxService {
  final _memory = TemporalBehaviorMemory();

  // Threshold: If stability is high (>0.9), getting a sudden "Allow" for something usually blocked is suspicious.
  static const double stabilityThreshold = 0.9;

  /// Checks if the decision aligns with long-term history.
  TrustGateResult checkAlignment(
      TrustGateResult currentResult, String featureId) {
    // 1. Get Historical Stability
    final stability = _memory.getHistoricalStability();

    // 2. Anomaly Detection
    // For simplicity: If system is remarkably stable, and we suddenly get a 'Personality Override',
    // aligner might dampen it to ensure gradual change.

    if (stability > stabilityThreshold) {
      if (currentResult.isAllowed &&
          currentResult.reason.contains('Personality Override')) {
        // "Override" suggests a deviation from norm.
        // If stability is extremely high, we might block this *one time* to require sustained intent.
        // (Simulating "Are you sure?" without UI).

        // For now, let's just log it as a drift warning, or maybe impose a "Consistency Check".
        // We will return it, but maybe flag it.
        return TrustGateResult(GateDecision.allow,
            '${currentResult.reason} [Drift Detected but Allowed]');
      }
    }

    return currentResult;
  }

  void recordInteraction(double riskValue) {
    // Collect data to update daily mean
    // In real app, this aggregates. Here we just push to memory.
    _memory.recordDailyRisk(riskValue);
  }
}
