/// Types of symbiosis trust relationship levels (G15).
enum SymbiosisTrustLevel {
  fullSync, // Human and system are aligned
  conditionalTrust, // Minor deviation detected
  underReview, // System decision questioned by human
  sovereignVeto, // System rejects human command for constitution
  detached, // Human authority suspended (Safe Detachment)
}

/// Category of human commands received by the system.
enum HumanCommandStatus {
  compatible, // Allowed by the G14 Constitution
  deferred, // Queued for safer conditions
  rejected, // Blocked by Constitutional Veto
}

/// Classification of system decisions for human understanding.
enum DecisionImplication {
  mandatory, // Non-negotiable constitutional requirement
  operational, // Optimization choice (can be influenced)
  advisory, // Suggestion for the human partner
}

/// A rationale model to explain "Why" the system acted (G15).
class SovereignRationale {
  final String decisionId;
  final String humanMessage; // The translated rationale for humans
  final DecisionImplication implication;
  final bool privacyPreserved;
  final DateTime timestamp;

  const SovereignRationale({
    required this.decisionId,
    required this.humanMessage,
    required this.implication,
    this.privacyPreserved = true,
    required this.timestamp,
  });
}

/// Audit log for the symbiosis relationship (Trust Matrix).
class SymbiosisAuditLog {
  final String interactionId;
  final SymbiosisTrustLevel trustLevel;
  final String humanInputSummary;
  final String systemResponseRationale;
  final HumanCommandStatus commandStatus;

  const SymbiosisAuditLog({
    required this.interactionId,
    required this.trustLevel,
    required this.humanInputSummary,
    required this.systemResponseRationale,
    required this.commandStatus,
  });
}
