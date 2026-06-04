import '../../personality/models/digital_personality.dart';
import '../../trust_ethics/gate/trust_decision_gate.dart';

/// Captures the full context of a decision for traceability.
class DecisionTrace {
  final String featureId;
  final String action;
  final GateDecision finalDecision;
  final String reason;

  // Influencers
  final double trustScore;
  final PersonalityType personality;
  final double riskLevel;
  final bool alignedWithHistory;

  final DateTime timestamp;

  DecisionTrace({
    required this.featureId,
    required this.action,
    required this.finalDecision,
    required this.reason,
    required this.trustScore,
    required this.personality,
    required this.riskLevel,
    required this.alignedWithHistory,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'Trace($featureId, ${finalDecision.name}, Risk:${riskLevel.toStringAsFixed(2)})';
}
