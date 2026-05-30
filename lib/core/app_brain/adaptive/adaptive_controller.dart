import 'package:get/get.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'adaptive_models.dart';

/// The Central Decision Engine for Product Stability.
class AdaptiveController extends GetxService {
  static AdaptiveController get instance => Get.find();

  final _currentLevel = PerformanceLevel.normal.obs;
  PerformanceLevel get currentLevel => _currentLevel.value;

  final _adjustments = <String, dynamic>{}.obs;
  Map<String, dynamic> get adjustments => _adjustments;

  final _signalsBuffer = <AdaptiveSignal>[];
  static const int _bufferLimit = 50;

  /// Returns the latest signal of each type for easy access by PredictiveEngine
  Map<AdaptiveSignalType, AdaptiveSignal?> get latestSignals {
    final Map<AdaptiveSignalType, AdaptiveSignal?> map = {};
    for (var type in AdaptiveSignalType.values) {
      map[type] = _getLatestSignal(type);
    }
    return map;
  }

  /// Process an incoming telemetry signal and decide if adaptation is needed.
  void processSignal(AdaptiveSignal signal) {
    AppLogger.info('AdaptiveEngine: Received Signal',
        context: {'signal': signal.toString()});

    _signalsBuffer.insert(0, signal);
    if (_signalsBuffer.length > _bufferLimit) _signalsBuffer.removeLast();

    _evaluateAdaptation();
  }

  void _evaluateAdaptation() {
    final lastMemory = _getLatestSignal(AdaptiveSignalType.memory);

    PerformanceLevel newLevel = PerformanceLevel.normal;
    final Map<String, dynamic> newAdjustments = {};
    String reason = 'System health stable';

    // 1. Rule-Based Evaluation
    if (lastMemory != null && lastMemory.value > 450) {
      // Assume value is MB for now
      newLevel = PerformanceLevel.strained;
      newAdjustments['reduce_animations'] = true;
      newAdjustments['clear_image_cache'] = true;
      reason =
          'High memory detected (${lastMemory.value.toStringAsFixed(1)}MB)';
    }

    if (lastMemory != null && lastMemory.value > 800) {
      newLevel = PerformanceLevel.critical;
      newAdjustments['disable_non_critical_features'] = true;
      newAdjustments['force_low_res_media'] = true;
      reason = 'CRITICAL memory limit reached';
    }

    // 2. Security Incident Evaluation
    final lastSecurity = _getLatestSignal(AdaptiveSignalType.securityThreat);
    if (lastSecurity != null) {
      newLevel = PerformanceLevel.critical;
      newAdjustments['lockdown_mode'] = true;
      newAdjustments['disable_webrtc'] = true;
      reason =
          'Security Threat Detected: ${lastSecurity.metadata?['security_threat'] ?? "Unknown"}';
    }

    // 3. Apply if changed
    if (newLevel != _currentLevel.value ||
        _hasAdjustmentsChanged(newAdjustments)) {
      _applyAdaptation(AdaptiveDecision(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        targetLevel: newLevel,
        adjustments: newAdjustments,
        reason: reason,
      ));
    }
  }

  void _applyAdaptation(AdaptiveDecision decision) {
    AppLogger.critical('ADAPTATION TRIGGERED: ${decision.targetLevel}',
        context: {
          'reason': decision.reason,
          'adjustments': decision.adjustments,
        });

    _currentLevel.value = decision.targetLevel;
    _adjustments.assignAll(decision.adjustments);

    // Notify features via GetX reactivity or EventBus
  }

  AdaptiveSignal? _getLatestSignal(AdaptiveSignalType type) {
    return _signalsBuffer.firstWhereOrNull((s) => s.type == type);
  }

  bool _hasAdjustmentsChanged(Map<String, dynamic> updated) {
    if (updated.length != _adjustments.length) return true;
    for (var key in updated.keys) {
      if (updated[key] != _adjustments[key]) return true;
    }
    return false;
  }
}
