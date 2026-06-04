import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/av_stability_models.dart';

/// AV Stability Controller (G3).
/// Monitors network health and adapts media quality autonomously.
class AVStabilityController extends GetxService {
  final _currentMetrics = Rxn<AVQualityMetrics>();
  final _currentDecision = StabilityDecision.maintain.obs;

  AVStabilityConfig _config = AVStabilityConfig();

  void updateConfig(AVStabilityConfig config) {
    _config = config;
  }

  /// Analyzes incoming metrics and issues a stability decision.
  StabilityDecision analyzeStability(AVQualityMetrics metrics) {
    _currentMetrics.value = metrics;

    StabilityDecision decision;
    if (metrics.rttMs > 800 || metrics.packetLoss > 0.3) {
      decision = StabilityDecision.terminate;
    } else if (metrics.isCritical) {
      decision = StabilityDecision.audioOnly;
    } else if (metrics.isUnstable) {
      if (_config.autoResolutionScaling && metrics.fps > 15) {
        decision = StabilityDecision.degradeResolution;
      } else if (_config.enableABR) {
        decision = StabilityDecision.lowerBitrate;
      } else {
        decision = StabilityDecision.maintain;
      }
    } else {
      decision = StabilityDecision.maintain;
    }

    if (_currentDecision.value != decision) {
      _currentDecision.value = decision;
      debugPrint('📉 AVStability: Decision CHANGED to ${decision.name}');
    }

    return decision;
  }

  StabilityDecision get currentDecision => _currentDecision.value;
  AVQualityMetrics? get lastMetrics => _currentMetrics.value;
}
