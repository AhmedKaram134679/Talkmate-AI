/// Supported Global Regulatory Frameworks.
enum RegulatoryFramework {
  gdpr, // General Data Protection Regulation (EU)
  aiAct, // EU AI Act (Risk-based governance)
  ccpa, // California Consumer Privacy Act
  hipaa, // Healthcare privacy (Technical context)
}

/// Legal classification of a system action or intervention.
enum LegalClassification {
  purelyTechnical,
  privacyCritical,
  safetyIntervention,
  complianceRequired,
}

/// A structured legal explanation for a system decision.
class LegalInterpretation {
  final RegulatoryFramework framework;
  final String legalArticle; // e.g. "GDPR Art. 32"
  final String justification; // Human-readable legal reasoning
  final LegalClassification classification;

  LegalInterpretation({
    required this.framework,
    required this.legalArticle,
    required this.justification,
    required this.classification,
  });
}

/// An encrypted, certified legal evidence pack (Non-Media).
class LegalEvidencePack {
  final String packId;
  final String sessionId;
  final String encryptedBlob; // AES-256 Encrypted technical logs
  final String digitalSignature; // Certified Sovereign Signature
  final List<LegalInterpretation> interpretations;
  final DateTime sealedAt;

  LegalEvidencePack({
    required this.packId,
    required this.sessionId,
    required this.encryptedBlob,
    required this.digitalSignature,
    required this.interpretations,
    required this.sealedAt,
  });
}
