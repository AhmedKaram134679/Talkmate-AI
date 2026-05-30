import 'package:get/get.dart';
import 'self_reflection_engine.dart';

/// Adjusts internal weights (Risk, Trust) based on Reflective Memory.
class BehaviorOptimizationEngine {
  final _reflectionEngine = Get.find<SelfReflectionEngine>();

  /// Returns a modifier (0.0 - 1.0) for Risk Tolerance.
  /// If we have high regret for High Risk actions in this context, we reduce tolerance.
  double getRiskAdjustment(String featureId, String contextKey) {
    final avgRegret = _reflectionEngine.getAverageRegret(featureId, contextKey);

    // Simplistic formula: High regret reduces risk appetite significantly.
    // If Regret is 0.8 -> Risk Adjustment is 0.2 (Very conservative)
    return (1.0 - avgRegret).clamp(0.1, 1.0);
  }

  /// Returns a modifier for Trust Threshold.
  /// If we regret trusting too easily, we increase the threshold (modifier > 1.0).
  double getTrustThresholdModifier(String featureId) {
    final contextKey = 'TrustBlock'; // Simplified key for trust related regrets
    final avgRegret = _reflectionEngine.getAverageRegret(featureId, contextKey);

    // If regret is high, we become 1.5x more suspicious (require higher trust)
    return 1.0 + (avgRegret * 0.5);
  }
}
