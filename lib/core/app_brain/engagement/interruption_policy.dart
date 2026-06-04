import '../app_brain.dart';
import '../app_events.dart';
import 'decision_model.dart';
import 'priority_matrix.dart';

/// InterruptionPolicy: Deterministic rules for feature conflicts.
class InterruptionPolicy {
  static EngagementDecision evaluate({
    required AppBrainEvent event,
    required AppSystemState currentState,
  }) {
    final basePriority = PriorityMatrix.getBasePriority(event.source);

    // 1. Emergency Overrides
    if (currentState == AppSystemState.emergency) {
      return EngagementDecision(
        outcome: DecisionOutcome.logOnly,
        reason: 'System in Emergency Lockdown',
        priority: 0,
      );
    }

    // 2. Specific Rule: Incoming Call while in Another Call
    if (currentState == AppSystemState.calling && event is CallEvent) {
      return EngagementDecision(
        outcome: DecisionOutcome.queue, // Treat as missed call
        reason: 'User already in call (Busy)',
        priority: PriorityMatrix.priorityCallIncoming,
      );
    }

    // 3. Specific Rule: Chat while in Call
    if (currentState == AppSystemState.calling && event is ChatEvent) {
      return EngagementDecision(
        outcome: DecisionOutcome.silent,
        reason: 'Silent background message during call',
        priority: PriorityMatrix.priorityChatMessage,
      );
    }

    // 4. Specific Rule: DND Mode
    if (event.metadata['is_dnd'] == true ||
        currentState == AppSystemState.background) {
      return EngagementDecision(
        outcome: DecisionOutcome.queue,
        reason: 'User in Background or DND',
        priority: basePriority,
      );
    }

    // 5. Default Fallthrough
    return EngagementDecision(
      outcome: DecisionOutcome.display,
      reason: 'Allowed by default policy',
      priority: basePriority,
    );
  }
}
