import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';

import 'release_models.dart';

/// The Release & Production Engine for TalkMate AI.
class ReleaseManager extends GetxService {
  static ReleaseManager get instance => Get.find();

  final _currentConfig = ReleaseConfig(
    version: AppConfig.appVersion,
    buildNumber: AppConfig.appBuildNumber,
    status: ReleaseStatus.active,
    environment:
        kDebugMode ? AppEnvironment.internal : AppEnvironment.production,
  ).obs;

  ReleaseConfig get currentConfig => _currentConfig.value;

  /// Validates the current release state against known production incidents.
  Future<void> validateInProduction() async {
    AppLogger.info(
        'Release: Validating Build ${currentConfig.version}+${currentConfig.buildNumber}');

    // In a real staging/prod setup, this would fetch from a remote config/API
    // Simulate a check that might trigger a rollback
    if (currentConfig.needsRollback) {
      _applyEmergencyRollback();
    }
  }

  void _applyEmergencyRollback() {
    AppLogger.critical(
        'EMERGENCY ROLLBACK INITIATED: Current build marked for withdrawal');
    // Implement logic to downgrade features or block non-essential flows
    _currentConfig.value = ReleaseConfig(
        version: currentConfig.version,
        buildNumber: currentConfig.buildNumber,
        status: ReleaseStatus.rollback,
        environment: currentConfig.environment,
        features: {
          'calls_v1': FeatureState.hardKill,
          'high_res_media': FeatureState.softDisabled,
        });
  }

  /// Strict Production Policy: Enforce immutable rules at runtime
  bool get isStrictProduction =>
      currentConfig.environment == AppEnvironment.production;

  void triggerHotfix(String reason) {
    AppLogger.warning('HOTFIX REQUESTED: $reason');
    // Logic to fetch remote patch or adjust flags
  }
}

// For use in bootstrapper/main
const bool kDebugMode = !bool.fromEnvironment('dart.vm.product');
