import '../ai/iaid_advisor.dart';
import '../app_brain.dart';
import '../app_events.dart';
import '../engagement/decision_model.dart';

/// IMLDecisionAdvisor: Interface for integrating external Machine Learning models.
abstract class IMLDecisionAdvisor extends IAIDecisionAdvisor {
  /// Loads a specific pre-trained model into the advisor.
  Future<void> loadModel(String modelPath);

  /// Analyzes historical trends to suggest new priority weights.
  Future<Map<String, double>> suggestPriorityWeights();
}

/// MockMLAdvisor: A placeholder for future ML integration.
class MockMLAdvisor implements IMLDecisionAdvisor {
  @override
  Future<void> loadModel(String modelPath) async {
    // Logic to load TensorFlow Lite or custom models
  }

  @override
  Future<Map<String, double>> suggestPriorityWeights() async {
    return {'chat': 0.8, 'calls': 1.1};
  }

  @override
  EngagementDecision getDecision({
    required AppBrainEvent event,
    required AppSystemState currentState,
    Map<String, dynamic>? context,
  }) {
    throw UnimplementedError('ML Model Decision logic needed.');
  }

  @override
  String provideReasoning(AppBrainEvent event, EngagementDecision decision) =>
      'ML Model reasoning';

  @override
  void updateContext(Map<String, dynamic> newContext) {}
}
