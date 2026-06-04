import '../app_brain/app_brain.dart';
import '../app_brain/engagement/decision_model.dart';
import '../app_brain/learning/user_behavior_model.dart';
import '../app_brain/presence_model.dart';

/// IBrainInspectable: Interface for inspecting the raw state of the App Brain.
abstract class IBrainInspectable {
  AppSystemState get currentState;
  DeviceEngagement get currentPresence;
  String get dominantFeature;
}

/// IDecisionTraceable: Interface for tracking the history of brain decisions.
abstract class IDecisionTraceable {
  List<ObservedDecision> get recentDecisions;
  void record(ObservedDecision decision);
}

/// ILearningObservable: Interface for inspecting the current learning state.
abstract class ILearningObservable {
  InteractionProfile get currentProfile;
  List<BehaviorPattern> get detectedPatterns;
  double getLastAdjustment(String source);
}

/// ObservedDecision: A data model representing a decision event for observability.
class ObservedDecision {
  final DateTime timestamp;
  final String eventType;
  final String source;
  final int priority;
  final DecisionOutcome outcome;
  final String reasoning;

  ObservedDecision({
    required this.eventType,
    required this.source,
    required this.priority,
    required this.outcome,
    required this.reasoning,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      '[$timestamp] $source -> $outcome ($priority): $reasoning';
}
