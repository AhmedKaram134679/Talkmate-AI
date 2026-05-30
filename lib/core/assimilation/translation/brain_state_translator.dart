import '../../predictive/predictive_contracts.dart';
import '../../resilience/resilience_contracts.dart';
import '../../self_optimization/adaptive_profiles.dart';
import '../contracts/definitions.dart';

/// BrainStateTranslator: Converts complex Brain knowledge into simple Feature signals.
///
/// It acts as a "Simplifier" so features don't need to know about BCI scores,
/// MTTH, or specific FailureTypes.
class BrainStateTranslator {
  /// Translates the collective state of the Brain into signals for features.
  static FeatureStateSignals translate({
    required BrainConfidence brainConfidence,
    required ResilienceState systemHealth,
    required DevicePowerMode powerMode,
    required NetworkProfile networkProfile,
  }) {
    // 1. Determine Network Instability
    bool isNetworkUnstable = false;
    final networkHealth = systemHealth.states[FailureType.network];

    if (networkHealth == SystemHealthState.failed ||
        networkHealth == SystemHealthState.degraded ||
        networkProfile == NetworkProfile.shaky ||
        networkProfile == NetworkProfile.offline) {
      isNetworkUnstable = true;
    }

    // 2. Determine Power Mode
    final bool isLowPower = (powerMode != DevicePowerMode.normal);

    // 3. Determine Backend Status
    bool isBackendDegraded = false;
    final backendHealth = systemHealth.states[FailureType.backendTimeout];

    if (backendHealth == SystemHealthState.degraded ||
        backendHealth == SystemHealthState.failed) {
      isBackendDegraded = true;
    }

    // 4. Bandwidth Calculation (Simulated logic based on profile)
    double bandwidth = double.infinity;
    if (networkProfile == NetworkProfile.limited) bandwidth = 100.0; // kbps
    if (isLowPower) bandwidth = 50.0; // Restrict data on low power

    return FeatureStateSignals(
      isNetworkUnstable: isNetworkUnstable,
      isLowPowerMode: isLowPower,
      isBackendDegraded: isBackendDegraded,
      isSecurityLockdown: brainConfidence.score < 20, // Example threshold
      allowedBandwidthKbps: bandwidth,
    );
  }
}
