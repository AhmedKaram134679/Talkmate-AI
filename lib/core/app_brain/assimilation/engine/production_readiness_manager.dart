import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/production_readiness_models.dart';

/// Production Readiness Manager (G10).
/// Orchestrates system stability, metrics, and emergency kill switches.
class ProductionReadinessManager extends GetxService {
  final _healthState = SystemHealthState.optimal.obs;
  final _activeKillSwitches = <FeatureKillSwitch>{}.obs;
  final _metricsHistory = <TechnicalMetrics>[].obs;

  SystemHealthState get healthState => _healthState.value;
  Set<FeatureKillSwitch> get activeKillSwitches => _activeKillSwitches;

  /// Updates system metrics without user content (G10).
  void pushMetrics(TechnicalMetrics metrics) {
    _metricsHistory.add(metrics);
    if (_metricsHistory.length > 100) {
      _metricsHistory.removeAt(0); // Capped history
    }

    // Auto-degradation logic
    if (metrics.cpuUsage > 90 || metrics.memoryUsageMB > 1024) {
      _degradeSystem('Resource Pressure Detected');
    }
  }

  void _degradeSystem(String reason) {
    if (_healthState.value == SystemHealthState.optimal) {
      _healthState.value = SystemHealthState.degraded;
      debugPrint('⚠️ SYSTEM DEGRADED: $reason');
    }
  }

  /// Activates a central kill switch for a feature (G10).
  void toggleKillSwitch(FeatureKillSwitch feature, bool active) {
    if (active) {
      _activeKillSwitches.add(feature);
      debugPrint('🛑 GLOBAL KILL SWITCH ACTIVATED: ${feature.name}');
    } else {
      _activeKillSwitches.remove(feature);
      debugPrint('✅ KILL SWITCH RELEASED: ${feature.name}');
    }
  }

  /// Checks if a feature is currently allowed by the production controller.
  bool isFeatureAllowed(FeatureKillSwitch feature) {
    return !_activeKillSwitches.contains(feature);
  }

  /// Implements Smart Recovery Logic after a failure.
  Future<void> runRecovery(Future<void> Function() action) async {
    _healthState.value = SystemHealthState.recovering;
    int retry = 0;
    while (retry < 3) {
      try {
        await action();
        _healthState.value = SystemHealthState.optimal;
        debugPrint('🔄 RECOVERY SUCCESSFUL after retry ${retry + 1}');
        return;
      } catch (e) {
        retry++;
        await Future.delayed(Duration(seconds: retry * 2));
      }
    }
    _healthState.value = SystemHealthState.unstable;
    debugPrint('🛑 RECOVERY FAILED after 3 retries.');
  }

  /// Emergency Hard Kill Signal for the entire production instance.
  void globalHardKill() {
    debugPrint(
        '🚨 GLOBAL SYSTEM HARD KILL: Shutting down all production pipelines.');
    for (var fs in FeatureKillSwitch.values) {
      _activeKillSwitches.add(fs);
    }
    _healthState.value = SystemHealthState.critical;
  }

  @override
  void onClose() {
    _metricsHistory.clear();
    super.onClose();
  }
}
