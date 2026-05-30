import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../metrics/regret_index.dart';
import '../models/decision_outcome.dart';

class ReflectionLesson {
  final String featureId;
  final String contextKey; // e.g. "Proactive_HighRisk"
  final double regret;
  final DateTime timestamp;

  ReflectionLesson(this.featureId, this.contextKey, this.regret)
      : timestamp = DateTime.now();

  @override
  String toString() =>
      'Lesson($contextKey, Regret:${regret.toStringAsFixed(2)})';
}

/// Analyzes outcomes and learns lessons.
class SelfReflectionEngine extends GetxService {
  final List<ReflectionLesson> _memory = [];

  void processOutcome(DecisionOutcome outcome) {
    final regret = RegretIndex.calculate(outcome);

    debugPrint(
        '🔮 Reflection: Processing Outcome for ${outcome.trace.featureId}. Regret: ${regret.toStringAsFixed(2)}');

    if (regret > 0.3) {
      // We learned something negative.
      _learnLesson(outcome, regret);
    } else {
      debugPrint('   ✨ No significant regret. Decision was acceptable.');
    }
  }

  void _learnLesson(DecisionOutcome outcome, double regret) {
    // Simplify context key for memory
    String key =
        '${outcome.trace.personality.name}_Risk${outcome.trace.riskLevel > 0.5 ? "High" : "Low"}';

    if (outcome.trace.reason.contains('Override')) {
      key += '_Override';
    }

    final lesson = ReflectionLesson(outcome.trace.featureId, key, regret);
    _memory.add(lesson);

    debugPrint(
        '   📚 Learned: High regret in context [$key]. Warning generated.');
  }

  // Retrieve average regret for a context
  double getAverageRegret(String featureId, String contextKey) {
    final lessons = _memory
        .where((l) => l.featureId == featureId && l.contextKey == contextKey)
        .toList();
    if (lessons.isEmpty) return 0.0;

    final double sum = lessons.map((l) => l.regret).reduce((a, b) => a + b);
    return sum / lessons.length;
  }
}
