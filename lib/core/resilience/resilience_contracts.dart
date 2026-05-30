import 'package:flutter/foundation.dart';

/// FailureType: Categories of possible system failures.
enum FailureType {
  network,
  backendTimeout,
  webSocketDisconnect,
  notificationDelivery,
  featureCrash,
  none
}

/// SystemHealthState: The current reliability state of a specific component.
enum SystemHealthState {
  healthy, // Full performance
  degraded, // Limited performance (latency/retries)
  failed // Feature unavailable
}

/// IFailureClassifier: Contract for components that analyze raw errors.
abstract class IFailureClassifier {
  FailureType classify(dynamic error, StackTrace? stack);
}

/// IDegradationStrategy: Contract for defining how to react to specific failures.
abstract class IDegradationStrategy {
  FailureType get targetFailure;
  void applyFallback();
  void recover();
}

/// ResilienceState: Current snapshot of system robustness.
@immutable
class ResilienceState {
  final Map<FailureType, SystemHealthState> states;
  final DateTime lastUpdated;

  const ResilienceState({
    required this.states,
    required this.lastUpdated,
  });

  factory ResilienceState.initial() => ResilienceState(
        states: {
          for (var v in FailureType.values) v: SystemHealthState.healthy
        },
        lastUpdated: DateTime.now(),
      );

  bool isFeatureAvailable(FailureType type) =>
      (states[type] ?? SystemHealthState.healthy) != SystemHealthState.failed;
}
