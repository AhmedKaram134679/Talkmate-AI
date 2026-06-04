/// Types of autonomous decisions the system can take (G14).
enum SovereignDecisionType {
  featureControl, // Enable/Disable features like Recording, AI
  qualityAdjustment, // Adaptive bitrate/res governance
  resourceBalancing, // CPU/RAM optimization
  securityHardKill, // Self-triggered emergency stop
  unitIsolation, // Isolate failing or compromised units
}

/// The constitutional status of a decision.
enum ConstitutionStatus {
  constitutional, // Fully compliant with G14 rules
  unconstitutional, // Violates privacy or stability
  emergencyOverride, // Triggered by Fail-Safe protocols
}

/// A log of an autonomous decision taken by the engine.
class AutonomousDecisionLog {
  final String decisionId;
  final SovereignDecisionType type;
  final String rationale; // Technical basis (from G13 metrics)
  final ConstitutionStatus status;
  final DateTime timestamp;
  final Map<String, dynamic> appliedConstraints;

  const AutonomousDecisionLog({
    required this.decisionId,
    required this.type,
    required this.rationale,
    required this.status,
    required this.timestamp,
    required this.appliedConstraints,
  });
}

/// Constitutional thresholds for autonomous triggers.
class ConstitutionalThresholds {
  static const double packetLossKill = 15.0; // %
  static const double cpuPressureDegrade = 85.0; // %
  static const double securityAnomalyThreshold = 0.9; // Confidence
}
