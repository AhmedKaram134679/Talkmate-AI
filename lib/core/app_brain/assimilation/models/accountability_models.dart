import 'package:talkmate_ai/core/app_brain/assimilation/models/session_sovereignty_models.dart';

/// Supported compliance profiles for different institutional contexts.
enum ComplianceProfile {
  consumer, // Max privacy, zero retention
  enterprise, // Audit-ready, extended metadata logs
  regulated, // High-compliance, full technical evidence packs
}

/// A structured technical explanation for a sovereign decision.
class DecisionExplanation {
  final String policyId;
  final String objective; // e.g. "Preserve System Stability"
  final String technicalBasis; // Abstracted diagnosis
  final String constitutionalArticle; // Reference to Governance Skeleton

  DecisionExplanation({
    required this.policyId,
    required this.objective,
    required this.technicalBasis,
    required this.constitutionalArticle,
  });
}

/// A sovereign audit record for accountability.
class AccountabilityRecord {
  final String recordId;
  final String sessionId;
  final SovereignAction action;
  final String authority; // Who triggered/approved (Host/System)
  final DecisionExplanation explanation;
  final DateTime timestamp;
  final String integrityHash; // To prevent log tampering

  AccountabilityRecord({
    required this.recordId,
    required this.sessionId,
    required this.action,
    required this.authority,
    required this.explanation,
    required this.timestamp,
    required this.integrityHash,
  });
}

/// A technical evidence pack for compliance auditing (Non-Media).
class SessionEvidencePack {
  final String sessionId;
  final ComplianceProfile profile;
  final List<AccountabilityRecord> auditTrail;
  final Map<String, dynamic> qualityMetrics; // Latency, Packet Loss trends
  final DateTime generatedAt;

  SessionEvidencePack({
    required this.sessionId,
    required this.profile,
    required this.auditTrail,
    required this.qualityMetrics,
    required this.generatedAt,
  });
}
