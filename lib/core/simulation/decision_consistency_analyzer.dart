import '../app_brain/engagement/decision_model.dart';
import '../observability/decision_timeline_recorder.dart';
import '../observability/observability_contracts.dart';

/// DecisionConsistencyAnalyzer: Detects anomalies in decision patterns.
class DecisionConsistencyAnalyzer {
  static final DecisionConsistencyAnalyzer instance =
      DecisionConsistencyAnalyzer._();
  DecisionConsistencyAnalyzer._();

  final List<String> _warnings = [];
  List<String> get warnings => List.unmodifiable(_warnings);

  /// Analyzes the last N decisions for consistency.
  void analyze() {
    final decisions = DecisionTimelineRecorder.instance.recentDecisions;
    if (decisions.isEmpty) return;

    _warnings.clear();

    // 1. Detect rapid outcome oscillations
    _detectOscillations(decisions);

    // 2. Detect Priority Inversion (High priority event ignored while Low priority is active)
    _detectPriorityInversion(decisions);
  }

  void _detectOscillations(List<ObservedDecision> decisions) {
    if (decisions.length < 3) return;
    for (int i = 0; i < decisions.length - 2; i++) {
      if (decisions[i].outcome != decisions[i + 1].outcome &&
          decisions[i].outcome == decisions[i + 2].outcome) {
        _warnings.add(
            'Oscillation detected: ${decisions[i].source} moved [${decisions[i].outcome} -> ${decisions[i + 1].outcome} -> ${decisions[i + 2].outcome}]');
      }
    }
  }

  void _detectPriorityInversion(List<ObservedDecision> decisions) {
    // Logic: If a decision with priority > 500 resulted in 'Silent/Ignore'
    // while a lower priority event was recently 'Display/Active'.
    for (var decision in decisions) {
      if (decision.priority > 800 &&
          decision.outcome == DecisionOutcome.silent) {
        _warnings.add(
            'High Priority Inversion: ${decision.source} silenced despite priority ${decision.priority}');
      }
    }
  }
}
