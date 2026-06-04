/// Operating Environments for TalkMate AI (G17).
enum SovereignEnvironment {
  development,
  staging,
  production,
}

/// System stability states for production monitoring (G17).
enum OperationalStability {
  optimal, // Everything running within production margins
  degraded, // System adapting to resource pressure (Silent Recovery)
  critical, // Hard Kill imminent for protection
}

/// Resource Constraints for Production Profiles (G17).
class ProductionResourceMargins {
  final double maxCpuUsage;
  final int maxMemoryMB;
  final bool enableSilenceMode; // Disable all non-critical logs

  const ProductionResourceMargins({
    required this.maxCpuUsage,
    required this.maxMemoryMB,
    this.enableSilenceMode = true,
  });
}

/// Production Snapshot for Audit (G17).
class OperationalSnapshot {
  final SovereignEnvironment environment;
  final OperationalStability stability;
  final DateTime timestamp;

  const OperationalSnapshot({
    required this.environment,
    required this.stability,
    required this.timestamp,
  });
}
