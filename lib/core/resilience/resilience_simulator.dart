import 'degradation_manager.dart';
import 'resilience_contracts.dart';

/// ResilienceSimulator: Extension for Simulation stage to trigger failures.
class ResilienceSimulator {
  static void simulateBackendDown() {
    DegradationManager.instance.reportFailure(FailureType.backendTimeout);
    DegradationManager.instance
        .reportFailure(FailureType.backendTimeout); // Force to 'failed'
  }

  void simulateNetworkLoss() {
    DegradationManager.instance.reportFailure(FailureType.network);
  }

  void restoreAll() {
    for (var type in FailureType.values) {
      DegradationManager.instance.reportSuccess(type);
    }
  }
}
