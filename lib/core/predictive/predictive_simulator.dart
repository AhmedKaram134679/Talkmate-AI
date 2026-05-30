import 'brain_confidence_index.dart';

/// PredictiveSimulator: Simulates precursors to failure for testing E5.
class PredictiveSimulator {
  static void simulateLatencyCreep() {
    // Slowly lower BCI
    BrainConfidenceIndex.instance.updateScore(65);
  }

  static void simulateImminentCollapse() {
    BrainConfidenceIndex.instance.updateScore(35);
  }

  static void restorePredictiveHealth() {
    BrainConfidenceIndex.instance.updateScore(100);
  }
}
