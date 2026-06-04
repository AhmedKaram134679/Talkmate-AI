import 'adaptive_profiles.dart';

/// SelfOptimizationSimulator: Mocks environmental changes to trigger optimization.
class SelfOptimizationSimulator {
  static void simulateLowBattery() {
    AdaptiveRuntimeProfiles.instance.updatePowerMode(DevicePowerMode.lowPower);
  }

  static void simulateCriticalBattery() {
    AdaptiveRuntimeProfiles.instance.updatePowerMode(DevicePowerMode.critical);
  }

  static void simulatePoorNetwork() {
    AdaptiveRuntimeProfiles.instance.updateNetwork(NetworkProfile.shaky);
  }

  static void restoreOptimalConditions() {
    AdaptiveRuntimeProfiles.instance.updatePowerMode(DevicePowerMode.normal);
    AdaptiveRuntimeProfiles.instance.updateNetwork(NetworkProfile.stable);
  }
}
