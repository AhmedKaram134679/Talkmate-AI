import 'package:get/get.dart';

import 'adaptive_profiles.dart';
import 'cost_engine.dart';
import 'decision_scoring_engine.dart';
import 'optimization_contracts.dart';

/// OptimizationBrain: The governor of efficiency and value.
class OptimizationBrain extends GetxService implements IOptimizationBrain {
  static OptimizationBrain get instance => Get.find<OptimizationBrain>();

  @override
  OptimizationDecision evaluate(String operationId, {double impact = 0.5}) {
    final cost = CostEngine.instance.calculateCost(operationId);
    final profile = AdaptiveRuntimeProfiles.instance;

    // Weight value based on current power mode
    double adjustedValue = impact;
    if (profile.powerMode.value == DevicePowerMode.lowPower) {
      adjustedValue *= 0.7;
    }
    if (profile.powerMode.value == DevicePowerMode.critical) {
      adjustedValue *= 0.3;
    }

    return DecisionScoringEngine.score(operationId, cost, adjustedValue);
  }
}
