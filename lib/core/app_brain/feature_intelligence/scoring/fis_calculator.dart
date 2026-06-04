import 'package:get/get.dart';
import '../memory/feature_memory_store.dart';
import '../models/experience_record.dart';

/// Calculates the Intelligence Score (FIS) for features.
/// FIS (0-100) represents how "adaptive" and "reliable" a feature is in the current context.
class FeatureIntelligenceScore extends GetxService {
  final FeatureMemoryStore _memory = Get.find<FeatureMemoryStore>();

  /// Calculate score for a feature in a specific context.
  ///
  /// 0-30:  Low Trust (Strict rules only)
  /// 30-70: Medium Trust (Allow mild degradation)
  /// 70-100: High Trust (Allow risky experiments)
  double calculateScore(String featureId, String contextHash) {
    final history = _memory.getRelevantHistory(featureId, contextHash);

    // Default score for new contexts (Optimistic start)
    if (history.isEmpty) return 75.0;

    double score = 50.0; // Base score

    for (var record in history) {
      switch (record.outcome) {
        case PolicyOutcome.success:
          score += 5.0; // Reward success
          break;
        case PolicyOutcome.degraded:
          score += 2.0; // Small reward for graceful degradation
          break;
        case PolicyOutcome.failure:
          score -= 10.0; // Heavy penalty for failure
          break;
        case PolicyOutcome.rejected:
          score -= 5.0; // Penalty for user annoyance
          break;
      }
    }

    // Clamp score
    return score.clamp(0.0, 100.0);
  }
}
