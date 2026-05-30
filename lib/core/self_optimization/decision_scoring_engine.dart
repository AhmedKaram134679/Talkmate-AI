import 'optimization_contracts.dart';

/// DecisionScoringEngine: Balances Value vs Cost using weighted algorithms.
class DecisionScoringEngine {
  static OptimizationDecision score(
      String id, CostAssessment cost, double value) {
    final netWorth = value - cost.totalScore;

    if (netWorth > 0.4) {
      return OptimizationDecision(
        action: OptimizationAction.execute,
        costScore: cost.totalScore,
        valueScore: value,
        reasoning: 'High value justifies cost.',
      );
    } else if (netWorth > 0.1) {
      return OptimizationDecision(
        action: OptimizationAction.downgrade,
        costScore: cost.totalScore,
        valueScore: value,
        reasoning: 'Marginal value. Recommend quality reduction.',
      );
    } else if (value < 0.2) {
      return OptimizationDecision(
        action: OptimizationAction.cancel,
        costScore: cost.totalScore,
        valueScore: value,
        reasoning: 'Cost exceeds value significantly.',
      );
    } else {
      return OptimizationDecision(
        action: OptimizationAction.defer,
        costScore: cost.totalScore,
        valueScore: value,
        reasoning: 'Neutral value. Defer to low-consumption window.',
      );
    }
  }
}
