import '../resilience/resilience_contracts.dart';
import 'recovery_orchestrator.dart';

/// SelfHealingSimulator: Mocks recovery events for developer testing.
class SelfHealingSimulator {
  static void simulateRecoveryTrigger(FailureType type) {
    RecoveryOrchestrator.instance.attemptRecovery(type);
  }

  static void simulateImmediateFullRecovery() {
    // Restoration logic
  }
}
