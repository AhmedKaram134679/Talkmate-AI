/// Levels of ethical impact for decisions (G16).
enum EthicalImpactLevel {
  dignityPreserving, // Action enhances or protects user dignity
  neutral, // Standard operational action
  highRisk, // Potential indirect harm to privacy or freedom
  moralViolation, // Direct violation of G16 core ethics
}

/// Core ethical values that TalkMate AI upholds (G16).
enum SovereignEthicalValue {
  humanDignity,
  absolutePrivacy,
  freedomOfExpression,
  powerTransparency,
  moralAbstinence, // Choosing NOT to use a capability
}

/// A record in the "Abstinence Ledger" (G16).
/// Documents technical capabilities the system refused to use for ethical reasons.
class EthicalAbstinenceRecord {
  final String capabilityName;
  final String rationale; // Why it was not used
  final SovereignEthicalValue protectedValue;
  final DateTime timestamp;

  const EthicalAbstinenceRecord({
    required this.capabilityName,
    required this.rationale,
    required this.protectedValue,
    required this.timestamp,
  });
}

/// An ethical rationale to explain "Should we do it?" (G16).
class EthicalRationale {
  final String decisionId;
  final String moralBasis; // The ethical principle
  final EthicalImpactLevel impact;
  final DateTime timestamp;

  const EthicalRationale({
    required this.decisionId,
    required this.moralBasis,
    required this.impact,
    required this.timestamp,
  });
}
