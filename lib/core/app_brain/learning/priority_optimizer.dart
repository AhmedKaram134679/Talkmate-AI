import 'user_behavior_model.dart';

/// PriorityOptimizer: Calculates dynamic score adjustments based on usage profile.
class PriorityOptimizer {
  /// Returns a multiplier (0.0 to 2.0) to adjust base priority.
  static double calculateAdjustment({
    required String source,
    required InteractionProfile profile,
  }) {
    final stats = profile.features[source];
    if (stats == null) return 1.0;

    double adjustment = 1.0;

    // 1. Penalty for high ignore rate
    if (stats.ignoreRate > 0.7) {
      adjustment *= 0.5; // Cut priority in half
    }

    // 2. Penalty/Bonus for response time
    if (stats.ignoreCount > 5) {
      // Logic: If user is generally slow/ignoring, degrade importance
      adjustment *= 0.8;
    }

    // 3. Time-based penalty (Mock Example: Lower priority at night if nightOwl is detected)
    final now = DateTime.now();
    final hourFreq = stats.hourlyDistribution[now.hour] ?? 0;
    if (hourFreq == 0 && stats.eventCount > 50) {
      // Unusual time for this feature? Lower priority to avoid jarring interrupt.
      adjustment *= 0.7;
    }

    return adjustment.clamp(0.2, 2.0);
  }

  /// Explains why an adjustment was made.
  static String getOptimizationReason(double adjustment) {
    if (adjustment < 1.0) {
      return 'Optimized: Lowered priority based on typical ignore patterns.';
    }
    if (adjustment > 1.0) {
      return 'Optimized: Increased priority due to high engagement history.';
    }
    return 'Default: No historical optimization applied.';
  }
}
