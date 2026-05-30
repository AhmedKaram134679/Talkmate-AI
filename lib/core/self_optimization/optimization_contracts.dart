import 'package:flutter/foundation.dart';

/// CostAssessment: Break down of resource consumption for an action.
@immutable
class CostAssessment {
  final double battery; // 0.0 to 1.0
  final double network; // 0.0 to 1.0
  final double backend; // 0.0 to 1.0
  final double uxDisruption; // 0.0 to 1.0

  const CostAssessment({
    this.battery = 0.0,
    this.network = 0.0,
    this.backend = 0.0,
    this.uxDisruption = 0.0,
  });

  double get totalScore => (battery + network + backend + uxDisruption) / 4.0;
}

/// OptimizationAction: Recommendation from the optimization brain.
enum OptimizationAction { execute, downgrade, defer, cancel }

/// OptimizationDecision: Detailed outcome of the scoring engine.
@immutable
class OptimizationDecision {
  final OptimizationAction action;
  final double costScore;
  final double valueScore;
  final String reasoning;

  const OptimizationDecision({
    required this.action,
    required this.costScore,
    required this.valueScore,
    required this.reasoning,
  });
}

/// IOptimizationBrain: Central logic for governing efficiency.
abstract class IOptimizationBrain {
  OptimizationDecision evaluate(String operationId, {double impact = 0.5});
}

/// ICostEngine: Multi-dimensional cost calculator.
abstract class ICostEngine {
  CostAssessment calculateCost(String operationId);
}
