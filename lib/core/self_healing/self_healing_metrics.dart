import '../resilience/resilience_contracts.dart';

/// SelfHealingMetrics: Tracks MTTH and success rates for automatic repairs.
class SelfHealingMetrics {
  static final SelfHealingMetrics instance = SelfHealingMetrics._();
  SelfHealingMetrics._();

  final Map<FailureType, int> _successfulRecoveries = {};
  final Map<FailureType, List<Duration>> _healingTimes = {};

  void recordSuccess(FailureType type, Duration timeToHeal) {
    _successfulRecoveries[type] = (_successfulRecoveries[type] ?? 0) + 1;
    _healingTimes[type] ??= [];
    _healingTimes[type]!.add(timeToHeal);
  }

  double calculateMTTH(FailureType type) {
    final times = _healingTimes[type];
    if (times == null || times.isEmpty) return 0.0;

    final totalMs = times.fold(0, (sum, d) => sum + d.inMilliseconds);
    return totalMs / times.length / 1000.0;
  }

  int getSuccessCount(FailureType type) => _successfulRecoveries[type] ?? 0;
}
