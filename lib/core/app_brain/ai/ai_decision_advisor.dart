import '../../observability/brain_control_panel.dart';
import '../app_brain.dart';
import '../app_events.dart';
import '../engagement/decision_model.dart';
import '../engagement/interruption_policy.dart';
import '../learning/behavior_tracker.dart';
import '../learning/priority_optimizer.dart';
import 'iaid_advisor.dart';

/// AIDecisionAdvisor: The adaptive implementation of the internal reasoning engine.
class AIDecisionAdvisor implements IAIDecisionAdvisor {
  final Map<String, dynamic> _localContext = {};

  @override
  EngagementDecision getDecision({
    required AppBrainEvent event,
    required AppSystemState currentState,
    Map<String, dynamic>? context,
  }) {
    // 1. Check if we have specialized context-based overrides
    if (_shouldApplyNetworkPolicy(event)) {
      return EngagementDecision(
        outcome: DecisionOutcome.queue,
        reason: 'Adaptive: Low bandwidth environment detection',
        priority: 10,
      );
    }

    // 2. Delegate to the deterministic InterruptionPolicy for baseline rules
    final baseline = InterruptionPolicy.evaluate(
      event: event,
      currentState: currentState,
    );

    // 3. AI Learning Layer: Adjust priority based on behavioral profile
    // [OBSERVABILITY]: Check if learning is disabled via Control Panel
    final learningAdjustment = BrainControlPanel.instance.shouldIgnoreLearning()
        ? 1.0
        : PriorityOptimizer.calculateAdjustment(
            source: event.source,
            profile: BehaviorTracker.instance.profile.value,
          );

    if (learningAdjustment != 1.0) {
      final adjustedPriority = (baseline.priority * learningAdjustment).toInt();
      return EngagementDecision(
        outcome:
            adjustedPriority < 200 ? DecisionOutcome.silent : baseline.outcome,
        reason:
            '${baseline.reason} | ${PriorityOptimizer.getOptimizationReason(learningAdjustment)}',
        priority: adjustedPriority,
        metadata: {
          ...baseline.metadata,
          'learning_adjustment': learningAdjustment,
        },
      );
    }

    return baseline;
  }

  @override
  String provideReasoning(AppBrainEvent event, EngagementDecision decision) {
    return 'Decision [$decision] triggered by [${event.source}]. Reasoning: ${decision.reason}';
  }

  @override
  void updateContext(Map<String, dynamic> newContext) {
    _localContext.addAll(newContext);
  }

  bool _shouldApplyNetworkPolicy(AppBrainEvent event) {
    final quality = _localContext['network_quality'] ?? 'good';
    // Logic: If network is poor and event is heavy (like a call hint), queue it.
    return quality == 'poor' && event is CallEvent;
  }
}
