import '../models/feature_priority_profile.dart';
import '../models/negotiation_request.dart';
import '../models/negotiation_result.dart';

/// Pure logic class that resolves conflicts between competing features.
/// Implements the "Degrade > Delay > Disable" strategy.
class PriorityArbitrator {
  /// Main Arbitration Method
  NegotiationResult arbitrate(
    NegotiationRequest request,
    FeaturePriorityProfile profile,
    int currentSystemLoad, // 0-100
    List<NegotiationResult> activeFeatures, // What's currently running
  ) {
    // 1. Calculate Effective Priority
    final int effectivePriority = profile.basePriority;

    // 2. Check Resource Constraints
    if (currentSystemLoad > 80) {
      // System is stressed. Only High/Critical allowed fully.
      if (effectivePriority < 70) {
        return _degradeOrDelay(request, profile, currentSystemLoad);
      }
    }

    // 3. Check Conflicts with Active Features
    for (var active in activeFeatures) {
      if (active.decision == NegotiationDecision.approve) {
        // Simple conflict check (Future: use Resource Tags)
        // If a Critical feature is running, lower priority requests might suffer.
        if (active.featureId == 'calls_v1' && request.featureId != 'calls_v1') {
          if (effectivePriority < 90) {
            // If not also critical
            return _degradeOrDelay(request, profile, currentSystemLoad);
          }
        }
      }
    }

    // Default: Approve
    return NegotiationResult.approved(request.featureId);
  }

  NegotiationResult _degradeOrDelay(
      NegotiationRequest request, FeaturePriorityProfile profile, int load) {
    // Strategy: Degrade -> Delay -> Reject

    // 1. Try Degrade (If feature supports it)
    // Note: In a real system, we'd check if constraints allow degradation.
    // For now, we assume we can suggest degradation constraints.
    if (load < 95) {
      return NegotiationResult(
          featureId: request.featureId,
          decision: NegotiationDecision.degrade,
          finalConstraints: {'quality': 'low', 'background_only': true},
          reason: 'System Load High / Conflict');
    }

    // 2. Try Delay (Background tasks)
    if (profile.basePriority < 40) {
      return NegotiationResult(
          featureId: request.featureId,
          decision: NegotiationDecision.delay,
          reason: 'Low Priority - Delayed');
    }

    // 3. Reject (Critical System State)
    return NegotiationResult.rejected(request.featureId, 'System Overload');
  }
}
