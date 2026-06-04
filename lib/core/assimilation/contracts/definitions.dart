// Shared Enums and Constants for Feature Assimilation.

/// The types of features the App Brain manages.
enum FeatureType {
  call,
  chat,
  notification,
  presence,
  search,
  mediaUpload,
  backgroundSync,
  room
}

/// The outcome of a feature access request.
enum FeatureAccessDecision {
  allow, // Full access granted.
  degrade, // Access granted but with reduced quality/functionality.
  queue, // Action deferred until conditions improve.
  block, // Access denied due to risk or policy.
  simulate // Allow in simulation mode only (no real side effects).
}

/// Specific requirements a feature needs to operate.
enum FeatureRequirement {
  internet,
  highBandwidth,
  lowLatency,
  camera,
  microphone,
  storageWrite,
  batteryHeavy,
  backgroundExecution
}

/// Simplified brain signals translated for features.
class FeatureStateSignals {
  final bool isNetworkUnstable;
  final bool isLowPowerMode;
  final bool isBackendDegraded;
  final bool isSecurityLockdown;
  final double allowedBandwidthKbps;

  const FeatureStateSignals({
    this.isNetworkUnstable = false,
    this.isLowPowerMode = false,
    this.isBackendDegraded = false,
    this.isSecurityLockdown = false,
    this.allowedBandwidthKbps = double.infinity,
  });

  factory FeatureStateSignals.optimal() => const FeatureStateSignals();

  factory FeatureStateSignals.restricted() => const FeatureStateSignals(
        isNetworkUnstable: true,
        isLowPowerMode: true,
        allowedBandwidthKbps: 50.0,
      );
}
