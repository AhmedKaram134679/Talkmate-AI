/// Levels of security risk detected
enum SecurityRiskLevel { low, medium, high, critical }

/// Types of security threats
enum SecurityThreatType { tampering, unauthorizedEnv, credentialRisk, piiLeak }

/// A security signal to be processed by the engine
class SecuritySignal {
  final SecurityThreatType type;
  final SecurityRiskLevel risk;
  final String source;
  final Map<String, dynamic>? details;
  final DateTime timestamp;

  SecuritySignal({
    required this.type,
    required this.risk,
    required this.source,
    this.details,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'SecuritySignal[${type.name}, Risk: ${risk.name}]';
}
