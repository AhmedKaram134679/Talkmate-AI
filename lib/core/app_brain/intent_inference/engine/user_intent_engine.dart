import 'package:get/get.dart';
import '../models/intent_hypothesis.dart';

/// Analyzes user behavior to infer intent.
class UserIntentEngine extends GetxService {
  /// In a real app, this would subscribe to global touch events or navigation streams.
  /// For now, we simulate "Action Analysis" based on metadata passed by the client.

  IntentHypothesis analyzeIntent(String featureId, String action,
      {Map<String, dynamic> context = const {}}) {
    try {
      // Heuristic 1: Repetition (Noise vs Urgent)
      final repetition = context['repetition_count'];
      if (repetition is int) {
        if (repetition > 5) {
          return IntentHypothesis(
              type: IntentType.noise,
              confidence: 0.9,
              reasoning: 'High repetition detected ($repetition)');
        } else if (repetition > 2) {
          return IntentHypothesis(
              type: IntentType.urgent,
              confidence: 0.75,
              reasoning: 'Repeated attempts ($repetition)');
        }
      }

      // Heuristic 2: Context Driven
      if (context['source'] == 'notification_tap' ||
          context['source'] == 'deep_link') {
        return IntentHypothesis(
            type: IntentType.contextDriven,
            confidence: 0.95,
            reasoning: 'Direct user interaction');
      }

      // Default
      return IntentHypothesis.unknown;
    } catch (e) {
      return IntentHypothesis.unknown;
    }
  }
}
