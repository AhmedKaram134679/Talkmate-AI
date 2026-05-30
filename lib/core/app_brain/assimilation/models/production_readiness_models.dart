/// Production Readiness States (G10).
enum SystemHealthState {
  optimal,
  degraded,
  unstable,
  recovering,
  critical,
}

/// Feature Kill Switches for central control.
enum FeatureKillSwitch {
  video,
  audio,
  recording,
  aiModeration,
  screenShare,
  groupSession,
}

/// Technical Performance Metrics (Anonymous).
class TechnicalMetrics {
  final double cpuUsage; // Percentage
  final double gpuUsage; // Percentage
  final int memoryUsageMB; // MB
  final int roundTripTimeMs; // Latency
  final double packetLoss; // Percentage
  final DateTime timestamp;

  const TechnicalMetrics({
    required this.cpuUsage,
    required this.gpuUsage,
    required this.memoryUsageMB,
    required this.roundTripTimeMs,
    required this.packetLoss,
    required this.timestamp,
  });
}

/// Recovery configuration.
class RecoveryPolicy {
  final int maxRetries;
  final Duration backoffStep;
  final bool autoResume;

  const RecoveryPolicy({
    this.maxRetries = 5,
    this.backoffStep = const Duration(seconds: 2),
    this.autoResume = true,
  });
}
