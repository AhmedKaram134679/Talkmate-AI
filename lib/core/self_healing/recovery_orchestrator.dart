import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../resilience/degradation_manager.dart';
import '../resilience/resilience_contracts.dart';
import 'self_healing_contracts.dart';

/// RecoveryOrchestrator: Coordinates retries and backoffs for failed features.
class RecoveryOrchestrator extends GetxService
    implements IRecoveryOrchestrator {
  static RecoveryOrchestrator get instance => Get.find<RecoveryOrchestrator>();

  final Map<FailureType, int> _retryCounts = {};
  final Map<FailureType, bool> _activeRecoveries = {};

  @override
  Future<void> attemptRecovery(FailureType type) async {
    if (isRecovering(type)) return;

    _activeRecoveries[type] = true;
    _retryCounts[type] = 0;

    final strategy = const RecoveryStrategy();

    while (_activeRecoveries[type] == true &&
        _retryCounts[type]! < strategy.maxRetries) {
      _retryCounts[type] = _retryCounts[type]! + 1;

      final delay = strategy.getDelay(_retryCounts[type]!);
      await Future.delayed(delay);

      debugPrint(
          'SelfHealing: Attempting recovery for $type (Try #${_retryCounts[type]})');

      // Mock probing logic check
      final success = await _fakeProbe(type);
      if (success) {
        _onRecoverySuccess(type);
        return;
      }
    }

    _onRecoveryFailed(type);
  }

  @override
  void stopRecovery(FailureType type) => _activeRecoveries[type] = false;

  @override
  bool isRecovering(FailureType type) => _activeRecoveries[type] ?? false;

  Future<bool> _fakeProbe(FailureType type) async =>
      false; // Interfaces only policy

  void _onRecoverySuccess(FailureType type) {
    _activeRecoveries[type] = false;
    DegradationManager.instance.reportSuccess(type);
  }

  void _onRecoveryFailed(FailureType type) {
    _activeRecoveries[type] = false;
    debugPrint('SelfHealing: Max retries reached for $type. Recovery aborted.');
  }
}
