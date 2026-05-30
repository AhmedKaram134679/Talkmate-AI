/// Network quality metrics for AV stability.
class AVQualityMetrics {
  final int rttMs; // Round Trip Time
  final double packetLoss; // 0.0 to 1.0
  final double jitterMs;
  final int fps;

  AVQualityMetrics({
    required this.rttMs,
    required this.packetLoss,
    required this.jitterMs,
    required this.fps,
  });

  bool get isCritical => rttMs > 500 || packetLoss > 0.15;
  bool get isUnstable => rttMs > 250 || packetLoss > 0.05;
}

/// Decisions taken by the stability engine.
enum StabilityDecision {
  maintain,
  degradeResolution,
  throttleFrameRate,
  lowerBitrate,
  audioOnly, // Emergency mode
  terminate, // Fatal condition
}

/// Configuration for AV adaptation.
class AVStabilityConfig {
  final bool enableABR;
  final bool autoResolutionScaling;
  final int minBitrateKbps;

  AVStabilityConfig({
    this.enableABR = true,
    this.autoResolutionScaling = true,
    this.minBitrateKbps = 128,
  });
}
