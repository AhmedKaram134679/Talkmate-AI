import '../app_brain.dart';
import '../app_events.dart';
import '../engagement/decision_model.dart';

/// IAIDecisionAdvisor: Interface for adaptive, intelligent decision making.
abstract class IAIDecisionAdvisor {
  /// Analyzes an event against the current system state and provides a decision.
  EngagementDecision getDecision({
    required AppBrainEvent event,
    required AppSystemState currentState,
    Map<String, dynamic>? context,
  });

  /// Explains the logic behind a specific decision.
  String provideReasoning(AppBrainEvent event, EngagementDecision decision);

  /// Allows for external context updates (e.g., network quality, user fatigue).
  void updateContext(Map<String, dynamic> newContext);
}
