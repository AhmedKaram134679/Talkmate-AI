import 'package:get/get.dart';
import 'resilience_contracts.dart';
import 'resilience_metrics.dart';

/// DegradationManager: Orchesrates fallback strategies based on detected failures.
class DegradationManager extends GetxController {
  static DegradationManager get instance =>
      Get.isRegistered<DegradationManager>()
          ? Get.find<DegradationManager>()
          : Get.put(DegradationManager());

  final Rx<ResilienceState> _currentState = ResilienceState.initial().obs;
  ResilienceState get currentState => _currentState.value;

  /// Reports a failure and determines if degradation is needed.
  void reportFailure(FailureType type) {
    if (type == FailureType.none) return;

    final updatedMap =
        Map<FailureType, SystemHealthState>.from(_currentState.value.states);

    // Simple state machine: healthy -> degraded -> failed
    if (updatedMap[type] == SystemHealthState.healthy) {
      updatedMap[type] = SystemHealthState.degraded;
    } else {
      updatedMap[type] = SystemHealthState.failed;
    }

    _currentState.value = ResilienceState(
      states: updatedMap,
      lastUpdated: DateTime.now(),
    );

    ResilienceMetricsTracker.instance.recordFailure(type);
    _logDegradation(type, updatedMap[type]!);
  }

  void reportSuccess(FailureType type) {
    if (_currentState.value.states[type] == SystemHealthState.healthy) return;

    final updatedMap =
        Map<FailureType, SystemHealthState>.from(_currentState.value.states);
    updatedMap[type] = SystemHealthState.healthy;

    _currentState.value = ResilienceState(
      states: updatedMap,
      lastUpdated: DateTime.now(),
    );

    ResilienceMetricsTracker.instance.recordRecovery(type);
  }

  void _logDegradation(FailureType type, SystemHealthState state) {
    Get.snackbar(
      'System Resilience',
      '${type.name.capitalizeFirst} is now ${state.name}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
