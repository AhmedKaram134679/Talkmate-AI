/// Types of enterprise systems supported for integration (G12).
enum EnterpriseSystemType {
  erp,
  lms,
  crm,
  hris,
  customWebhook,
  externalAuth,
}

/// Connection states for sovereign enterprise bridges.
enum IntegrationBridgeState {
  disconnected,
  handshaking,
  active,
  throttled,
  interrupted,
  hardKilled,
}

/// Audit model for enterprise data exchange.
class EnterpriseAuditLog {
  final String integrationId;
  final EnterpriseSystemType systemType;
  final String action;
  final String userId;
  final DateTime timestamp;
  final bool isVetoed; // If sovereign rules blocked it

  const EnterpriseAuditLog({
    required this.integrationId,
    required this.systemType,
    required this.action,
    required this.userId,
    required this.timestamp,
    this.isVetoed = false,
  });
}

/// Configuration for an Enterprise API Bridge.
class EnterpriseApiConfig {
  final String bridgeId;
  final String endpoint;
  final EnterpriseSystemType systemType;
  final Map<String, String> headers;
  final bool requireSovereignConsent;

  const EnterpriseApiConfig({
    required this.bridgeId,
    required this.endpoint,
    required this.systemType,
    this.headers = const {},
    this.requireSovereignConsent = true,
  });
}
