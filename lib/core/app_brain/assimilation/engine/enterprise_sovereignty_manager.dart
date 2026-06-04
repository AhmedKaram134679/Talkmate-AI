import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/accountability_models.dart';
import '../models/enterprise_sovereignty_models.dart';

/// Enterprise Sovereignty Manager (F7).
/// Manages multi-tenant isolation and per-enterprise governance.
class EnterpriseSovereigntyManager extends GetxService {
  final Map<String, EnterpriseIdentity> _registeredEnterprises = {};
  final Map<String, EnterpriseSessionContext> _activeContexts = {};

  @override
  void onInit() {
    super.onInit();
    // Register default organization for standard users
    registerEnterprise(EnterpriseIdentity(
      orgId: 'default_org',
      name: 'TalkMate Public',
      trustLevel: EnterpriseTrustLevel.sovereign,
      governanceProfile: EnterpriseGovernanceProfile.flexible,
      complianceProfile: ComplianceProfile.consumer,
    ));
  }

  /// Registers or updates an enterprise in the sovereignty registry.
  void registerEnterprise(EnterpriseIdentity identity) {
    debugPrint(
        '🏢 EnterpriseSovereignty: Registering ${identity.name} [ID: ${identity.orgId}]');
    _registeredEnterprises[identity.orgId] = identity;
  }

  /// Initializes a session context for a specific enterprise.
  EnterpriseSessionContext? initializeSessionContext(
      String orgId, String sessionId) {
    final enterprise = _registeredEnterprises[orgId];
    if (enterprise == null) {
      debugPrint('🛑 EnterpriseSovereignty: UNKNOWN Enterprise ID $orgId');
      return null;
    }

    // Default adaptive profile based on trust level
    final profile = _createDefaultProfile(enterprise.trustLevel);

    final context = EnterpriseSessionContext(
      orgId: orgId,
      sessionId: sessionId,
      adaptiveProfile: profile,
    );

    _activeContexts[sessionId] = context;
    debugPrint(
        '✅ EnterpriseSovereignty: Context INITIALIZED for $sessionId under ${enterprise.name}');
    return context;
  }

  EnterpriseAdaptiveProfile _createDefaultProfile(EnterpriseTrustLevel level) {
    switch (level) {
      case EnterpriseTrustLevel.sovereign:
        return EnterpriseAdaptiveProfile(
            maxBitrateKbps: 4000, maxParticipants: 500, priorityFactor: 1.0);
      case EnterpriseTrustLevel.premium:
        return EnterpriseAdaptiveProfile(
            maxBitrateKbps: 2000, maxParticipants: 100, priorityFactor: 0.8);
      default:
        return EnterpriseAdaptiveProfile(
            maxBitrateKbps: 1000, maxParticipants: 25, priorityFactor: 0.5);
    }
  }

  /// Returns the current context for a session.
  EnterpriseSessionContext? getContext(String sessionId) =>
      _activeContexts[sessionId];

  /// Purges enterprise-specific session data.
  void purgeEnterpriseContext(String sessionId) {
    debugPrint('🧼 EnterpriseSovereignty: Purging context for $sessionId.');
    _activeContexts.remove(sessionId);
  }
}
