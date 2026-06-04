import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../observability/decision_timeline_recorder.dart';
import '../../observability/observability_contracts.dart';
import '../../predictive/brain_confidence_index.dart';
import '../../resilience/degradation_manager.dart';
import '../../resilience/resilience_contracts.dart';
import '../../self_optimization/optimization_brain.dart';
import '../../self_optimization/optimization_contracts.dart';
import '../ai/ai_decision_advisor.dart';
import '../ai/iaid_advisor.dart';
import '../app_brain.dart';
import '../app_events.dart';
import '../engagement/decision_model.dart';

/// EngagementEngine: The implementation of the decision router.
class EngagementEngine extends GetxService {
  static EngagementEngine get instance => Get.find<EngagementEngine>();

  final _brain = Get.find<IAppBrain>();
  final List<DecisionLogEntry> _history = [];
  late final IAIDecisionAdvisor _advisor;

  void init({IAIDecisionAdvisor? advisor}) {
    _advisor = advisor ?? AIDecisionAdvisor();
    debugPrint(
        'EngagementEngine: Initializing decision router with [${_advisor.runtimeType}]...');
    _brain.eventBus.listen(_handleEvent);
  }

  void _handleEvent(AppBrainEvent event) {
    var decision = _advisor.getDecision(
      event: event,
      currentState: _brain.state.value,
    );

    // [PREDICTIVE]: Check Brain Confidence Index (BCI)
    decision = _applyPredictiveGuards(decision);

    // [OPTIMIZATION]: Check if decision is worth the cost
    decision = _applyOptimizationFilters(event, decision);

    // [RESILIENCE]: Check if feature is failed and downgrade decision
    decision = _applyResilienceFilters(event, decision);

    // [OBSERVABILITY]: Record decision in timeline
    DecisionTimelineRecorder.instance.record(ObservedDecision(
      eventType: event.runtimeType.toString(),
      source: event.source,
      priority: decision.priority,
      outcome: decision.outcome,
      reasoning: decision.reason,
    ));

    // Audit log
    _history.add(DecisionLogEntry(
      eventType: event.runtimeType.toString(),
      source: event.source,
      decision: decision,
      systemState: _brain.state.value.name,
    ));

    debugPrint('EngagementEngine: $decision');

    // Execute outcome (Abstraction for later linking)
    _executeDecision(event, decision);
  }

  void _executeDecision(AppBrainEvent event, EngagementDecision decision) {
    switch (decision.outcome) {
      case DecisionOutcome.display:
        // Future: Trigger high-priority notification UI
        break;
      case DecisionOutcome.queue:
        // Future: Store in "Pending Notifications" or "Missed Activity"
        break;
      case DecisionOutcome.silent:
        // Future: Increment unread count but skip alert
        break;
      case DecisionOutcome.cancel:
      case DecisionOutcome.logOnly:
        break;
    }
  }

  EngagementDecision _applyPredictiveGuards(EngagementDecision decision) {
    final bci = BrainConfidenceIndex.instance.current;

    if (bci.preventCritical) {
      return EngagementDecision(
        priority: 0,
        outcome: DecisionOutcome.cancel,
        reason: 'BCI CRITICAL (<40): Suppressing all brain activity.',
      );
    }

    if (bci.smartRestriction && decision.priority < 2) {
      return EngagementDecision(
        priority: decision.priority,
        outcome: DecisionOutcome.silent,
        reason: 'BCI STRATEGIC (40-69): Silencing low priority decisions.',
      );
    }

    return decision;
  }

  EngagementDecision _applyOptimizationFilters(
      AppBrainEvent event, EngagementDecision decision) {
    // Generate a unique operation ID based on event type
    final opId = event.runtimeType.toString();

    // Normalize priority (0-3) to impact (0.0-1.0)
    final impact = (decision.priority + 1) / 4.0;

    final opt = OptimizationBrain.instance.evaluate(opId, impact: impact);

    if (opt.action == OptimizationAction.cancel) {
      return EngagementDecision(
        priority: 0,
        outcome: DecisionOutcome.cancel,
        reason:
            'Optimization: ${opt.reasoning} (Cost: ${opt.costScore.toStringAsFixed(2)})',
      );
    }

    if (opt.action == OptimizationAction.defer) {
      return EngagementDecision(
        priority: decision.priority,
        outcome: DecisionOutcome.queue,
        reason: 'Optimization: ${opt.reasoning} (Deferrd due to efficiency)',
      );
    }

    if (opt.action == OptimizationAction.downgrade) {
      return EngagementDecision(
        priority: decision.priority,
        outcome: DecisionOutcome.silent,
        reason: 'Optimization: ${opt.reasoning} (Operating in Eco-Mode)',
      );
    }

    return decision;
  }

  EngagementDecision _applyResilienceFilters(
      AppBrainEvent event, EngagementDecision decision) {
    final health = DegradationManager.instance.currentState;

    if (event is CallEvent && !health.isFeatureAvailable(FailureType.network)) {
      return EngagementDecision(
        priority: 0,
        outcome: DecisionOutcome.cancel,
        reason: 'Resilience: Network unavailable for calls',
      );
    }

    if (event is ChatEvent &&
        !health.isFeatureAvailable(FailureType.webSocketDisconnect)) {
      return EngagementDecision(
        priority: decision.priority,
        outcome: DecisionOutcome.queue,
        reason: 'Resilience: WebSocket down, queuing message',
      );
    }

    return decision;
  }

  List<DecisionLogEntry> get history => List.unmodifiable(_history);
}
