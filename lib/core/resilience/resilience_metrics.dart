import 'resilience_contracts.dart';

/// ResilienceMetricsTracker: Tracks TTR and system survival rates.
class ResilienceMetricsTracker {
  static final ResilienceMetricsTracker instance = ResilienceMetricsTracker._();
  ResilienceMetricsTracker._();

  final Map<FailureType, List<DateTime>> _failureHistory = {};
  final Map<FailureType, List<Duration>> _recoveryTimes = {};

  void recordFailure(FailureType type) {
    _failureHistory[type] ??= [];
    _failureHistory[type]!.add(DateTime.now());
  }

  void recordRecovery(FailureType type) {
    if (_failureHistory[type] == null || _failureHistory[type]!.isEmpty) return;

    final lastFailure = _failureHistory[type]!.last;
    final recoveryDuration = DateTime.now().difference(lastFailure);

    _recoveryTimes[type] ??= [];
    _recoveryTimes[type]!.add(recoveryDuration);
  }

  double calculateAverageTTR(FailureType type) {
    final times = _recoveryTimes[type];
    if (times == null || times.isEmpty) return 0.0;

    final totalMs =
        times.fold(0, (sum, duration) => sum + duration.inMilliseconds);
    return totalMs / times.length / 1000.0; // Seconds
  }

  int getFailureCount(FailureType type) => _failureHistory[type]?.length ?? 0;

  double getFeatureSurvivalRate(FailureType type) {
    // Mock calculation: 1.0 - (failures / total expected checks)
    // In a real system, this would be based on uptime.
    final failures = getFailureCount(type);
    if (failures == 0) return 1.0;
    return (1.0 - (failures * 0.01)).clamp(0.0, 1.0);
  }
}
