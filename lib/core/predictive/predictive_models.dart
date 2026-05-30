/// Types of predictions the engine can make
enum PredictionType {
  crashRisk,
  memoryExhaustion,
  networkStability,
  behavioralDrop
}

/// Confidence level of the prediction
enum PredictionConfidence { low, medium, high, certain }

/// A prediction event from the engine
class PredictiveAlarm {
  final PredictionType type;
  final PredictionConfidence confidence;
  final double probability; // 0.0 to 1.0
  final Map<String, dynamic>? evidence;
  final DateTime timestamp;

  PredictiveAlarm({
    required this.type,
    required this.confidence,
    required this.probability,
    this.evidence,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'PredictiveAlarm[${type.name}, Confidence: ${confidence.name}]';
}

/// A self-healing action to be executed
class HealingAction {
  final String id;
  final String description;
  final void Function() execute;
  final bool silent;

  HealingAction({
    required this.id,
    required this.description,
    required this.execute,
    this.silent = true,
  });
}
