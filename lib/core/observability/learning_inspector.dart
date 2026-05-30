import '../app_brain/learning/behavior_tracker.dart';
import '../app_brain/learning/priority_optimizer.dart';
import '../app_brain/learning/user_behavior_model.dart';
import 'observability_contracts.dart';

/// LearningInspector: Introspects the current state of the Smart Learning Layer.
class LearningInspector implements ILearningObservable {
  static final LearningInspector instance = LearningInspector._();
  LearningInspector._();

  final _tracker = BehaviorTracker.instance;

  @override
  InteractionProfile get currentProfile => _tracker.profile.value;

  @override
  List<BehaviorPattern> get detectedPatterns {
    // Note: BehaviorTracker logger holds the pattern detection logic
    return _tracker.logger.detectEmergingPatterns();
  }

  @override
  double getLastAdjustment(String source) {
    return PriorityOptimizer.calculateAdjustment(
      source: source,
      profile: currentProfile,
    );
  }
}
