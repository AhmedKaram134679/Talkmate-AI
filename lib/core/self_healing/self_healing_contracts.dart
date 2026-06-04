import 'package:flutter/foundation.dart';
import '../resilience/resilience_contracts.dart';

/// IRecoveryOrchestrator: Manages the lifecycle of a recovery attempt.
abstract class IRecoveryOrchestrator {
  Future<void> attemptRecovery(FailureType type);
  void stopRecovery(FailureType type);
  bool isRecovering(FailureType type);
}

/// IHealthProber: Performs periodic checks to see if a feature is back online.
abstract class IHealthProber {
  Future<bool> probe(FailureType type);
  Stream<SystemHealthState> monitor(FailureType type);
}

/// RecoveryStrategy: Defines how many times and how often to retry.
@immutable
class RecoveryStrategy {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;

  const RecoveryStrategy({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 5),
    this.backoffMultiplier = 2.0,
  });

  Duration getDelay(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    return initialDelay * (backoffMultiplier * (retryCount - 1));
  }
}
