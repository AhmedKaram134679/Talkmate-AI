import 'dart:async';

import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_controller.dart';
import 'package:talkmate_ai/core/app_brain/adaptive/adaptive_models.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';

import 'predictive_models.dart';
import 'self_healing_controller.dart';

/// The Intelligent "Early Warning System" for TalkMate AI.
class PredictiveEngine extends GetxService {
  static PredictiveEngine get instance => Get.find();

  final _activeAlarms = <PredictiveAlarm>[].obs;
  List<PredictiveAlarm> get activeAlarms => _activeAlarms;
  Timer? _forecastTimer;

  /// Starts analyzing system health trends
  void startForecasting() {
    AppLogger.info(
        'Predictive: Intelligence Layer Active. Forecasting initialized.');

    // Cancel existing timer before spawning new one
    _forecastTimer?.cancel();
    // Cycle every minute to analyze trends
    _forecastTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _analyzeTrends();
    });
  }

  void stopForecasting() {
    _forecastTimer?.cancel();
    _forecastTimer = null;
  }

  @override
  void onClose() {
    stopForecasting();
    super.onClose();
  }

  void _analyzeTrends() {
    final adaptive = AdaptiveController.instance;

    // 1. Memory Exhaustion Trend Analysis
    final memorySignal = _getLatestMemorySignal(adaptive);
    if (memorySignal != null && memorySignal.value > 700) {
      _triggerAlarm(PredictiveAlarm(
        type: PredictionType.memoryExhaustion,
        confidence: PredictionConfidence.high,
        probability: 0.85,
        evidence: {'ram_usage': memorySignal.value, 'trend': 'rising_fast'},
      ));
    }

    // 2. Behavioral Drop Prediction
    final errorRate = _getLatestErrorRate(adaptive);
    if (errorRate != null && errorRate.value > 0.05) {
      _triggerAlarm(PredictiveAlarm(
        type: PredictionType.behavioralDrop,
        confidence: PredictionConfidence.medium,
        probability: 0.6,
        evidence: {'error_rate': errorRate.value},
      ));
    }
  }

  void _triggerAlarm(PredictiveAlarm alarm) {
    if (!_activeAlarms.any((a) => a.type == alarm.type)) {
      _activeAlarms.add(alarm);
      AppLogger.warning('PREDICTIVE ALARM: ${alarm.type.name} detected');

      // Notify Self-Healing
      SelfHealingController.instance.handleAlarm(alarm);
    }
  }

  AdaptiveSignal? _getLatestMemorySignal(AdaptiveController controller) {
    // In a real implementation, we would access the history of signals
    return controller.latestSignals[AdaptiveSignalType.memory];
  }

  AdaptiveSignal? _getLatestErrorRate(AdaptiveController controller) {
    return controller.latestSignals[AdaptiveSignalType.errorRate];
  }

  void clearAlarm(PredictionType type) {
    _activeAlarms.removeWhere((a) => a.type == type);
  }
}
