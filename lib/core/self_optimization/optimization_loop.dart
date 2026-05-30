import 'package:flutter/foundation.dart';

/// OptimizationFeedbackLoop: Learns from system results to adjust weights.
class OptimizationFeedbackLoop {
  static final OptimizationFeedbackLoop instance = OptimizationFeedbackLoop._();
  OptimizationFeedbackLoop._();

  final Map<String, List<double>> _performanceHistory = {};

  void recordOutcome(String opId, double gain) {
    _performanceHistory[opId] ??= [];
    _performanceHistory[opId]!.add(gain);

    debugPrint(
        'OptimizationLoop: Recorded gain of $gain for $opId. System is learning...');
  }

  double getAverageGain(String opId) {
    final list = _performanceHistory[opId];
    if (list == null || list.isEmpty) {
      return 0.5;
    }
    return list.reduce((a, b) => a + b) / list.length;
  }
}
