/// Levels of system performance and health
enum PerformanceLevel { high, normal, strained, critical }

/// Types of signals the Adaptive Engine can process
enum AdaptiveSignalType {
  memory,
  jitter,
  battery,
  errorRate,
  userActivity,
  securityThreat
}

/// A piece of telemetry metadata that triggers adaptation
class AdaptiveSignal {
  final AdaptiveSignalType type;
  final double value; // Normalized value 0.0 to 1.0 (or raw value)
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  AdaptiveSignal({
    required this.type,
    required this.value,
    this.metadata,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'AdaptiveSignal[${type.name}: $value]';
}

/// A decision made by the Adaptive Engine
class AdaptiveDecision {
  final String id;
  final PerformanceLevel targetLevel;
  final Map<String, dynamic> adjustments;
  final String reason;

  AdaptiveDecision({
    required this.id,
    required this.targetLevel,
    required this.adjustments,
    required this.reason,
  });
}
