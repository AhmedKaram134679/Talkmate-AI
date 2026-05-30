/// Types of sovereign analytical metrics (G13).
enum AnalyticsMetricType {
  latency,
  jitter,
  packetLoss,
  bitrate,
  cpuPressure,
  memoryPressure,
  sessionStability,
}

/// Predicted health states for a session.
enum SessionPredictedHealth {
  excellent,
  stable,
  degrading,
  criticalFailureImminent,
  disconnected,
}

/// A sovereign granular data point for technical analysis.
class SovereignDataPoint {
  final AnalyticsMetricType type;
  final double value;
  final DateTime timestamp;

  const SovereignDataPoint({
    required this.type,
    required this.value,
    required this.timestamp,
  });
}

/// A comprehensive sovereign session report (G13).
class SovereignSessionReport {
  final String sessionId;
  final DateTime startTime;
  final DateTime endTime;
  final Map<AnalyticsMetricType, double> averageMetrics;
  final List<String> events;
  final SessionPredictedHealth finalHealth;

  const SovereignSessionReport({
    required this.sessionId,
    required this.startTime,
    required this.endTime,
    required this.averageMetrics,
    required this.events,
    required this.finalHealth,
  });
}
