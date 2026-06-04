import 'accountability_models.dart';

/// Level of sovereignty granted to an enterprise.
enum EnterpriseTrustLevel {
  standard,
  premium,
  sovereign, // Full control over metadata and retention
}

/// Governance profiles for institutions.
enum EnterpriseGovernanceProfile {
  strict, // No guests, high encryption
  flexible, // Allows external invites
  broadcast, // Optimized for one-to-many
}

/// Model for an Enterprise/Client in TalkMate AI.
class EnterpriseIdentity {
  final String orgId;
  final String name;
  final EnterpriseTrustLevel trustLevel;
  final EnterpriseGovernanceProfile governanceProfile;
  final ComplianceProfile complianceProfile;

  EnterpriseIdentity({
    required this.orgId,
    required this.name,
    required this.trustLevel,
    required this.governanceProfile,
    required this.complianceProfile,
  });
}

/// Adaptive performance profile specific to an institution.
class EnterpriseAdaptiveProfile {
  final int maxBitrateKbps;
  final int maxParticipants;
  final bool allowHighVideo;
  final double priorityFactor; // 0.0 to 1.0 (Resource allocation weight)

  EnterpriseAdaptiveProfile({
    required this.maxBitrateKbps,
    required this.maxParticipants,
    this.allowHighVideo = true,
    this.priorityFactor = 0.5,
  });
}

/// Context of a specific session within an enterprise.
class EnterpriseSessionContext {
  final String orgId;
  final String sessionId;
  final EnterpriseAdaptiveProfile adaptiveProfile;

  EnterpriseSessionContext({
    required this.orgId,
    required this.sessionId,
    required this.adaptiveProfile,
  });
}
