import '../../self_awareness/models/decision_trace.dart';

enum OutcomeStatus {
  success,
  failure, // System failure (crash, error)
  rejectedByUser, // User explicitly undid/closed it
}

/// Represents the actual result of a decision after execution.
class DecisionOutcome {
  final DecisionTrace trace; // Link to the original decision
  final OutcomeStatus status;
  final double satisfactionScore; // 0.0 (Hated it) - 1.0 (Loved it)
  final DateTime timestamp;

  DecisionOutcome({
    required this.trace,
    required this.status,
    required this.satisfactionScore,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'Outcome(${trace.featureId}, ${status.name}, Score:$satisfactionScore)';
}
