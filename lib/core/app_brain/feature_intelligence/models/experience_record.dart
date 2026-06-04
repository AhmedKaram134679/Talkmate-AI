/// Result of applying a policy.
enum PolicyOutcome {
  success, // Feature worked perfectly
  degraded, // Feature worked but with issues (lag, etc.)
  failure, // Feature crashed or was unusable
  rejected, // User manually rejected the adaptation
}

/// Represents a single historical "experiment" or event for a feature.
class ExperienceRecord {
  final String featureId;
  final String contextHash; // Simple hash of state (e.g. "calling_networkLow")
  final Map<String, dynamic> policyApplied;
  final PolicyOutcome outcome;
  final DateTime timestamp;

  ExperienceRecord({
    required this.featureId,
    required this.contextHash,
    required this.policyApplied,
    required this.outcome,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'Experience($featureId, hash=$contextHash, outcome=${outcome.name})';
  }
}
