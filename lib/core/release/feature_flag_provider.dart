import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'release_manager.dart';
import 'release_models.dart';

/// Controls Feature Flags at the Production Level.
class FeatureFlagProvider extends GetxService {
  static FeatureFlagProvider get instance => Get.find();

  final _dynamicFlags = <String, FeatureState>{}.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeDefaultFlags();
  }

  void _initializeDefaultFlags() {
    // Initial sync with AppConfig
    _dynamicFlags['global_calls'] = AppConfig.globalCallsEnabled
        ? FeatureState.enabled
        : FeatureState.disabled;
    _dynamicFlags['voice_calls'] = AppConfig.enableVoiceCalls
        ? FeatureState.enabled
        : FeatureState.disabled;
    // ... add more as needed
  }

  /// Checks if a feature is allowed to run based on dynamic flags and release status.
  FeatureState getFeatureState(String featureId) {
    // 1. Check Release Rollback overrides first
    final releaseFeatures = ReleaseManager.instance.currentConfig.features;
    if (releaseFeatures.containsKey(featureId)) {
      return releaseFeatures[featureId]!;
    }

    // 2. Check Dynamic Flags
    return _dynamicFlags[featureId] ?? FeatureState.enabled;
  }

  /// Update a flag in runtime (Remote Config equivalent)
  void updateFlag(String featureId, FeatureState state) {
    _dynamicFlags[featureId] = state;
    // Log change
  }

  bool isEnabled(String featureId) {
    final state = getFeatureState(featureId);
    return state == FeatureState.enabled || state == FeatureState.softDisabled;
  }

  bool isHighPerformanceAllowed() {
    return !ReleaseManager.instance.currentConfig.needsRollback;
  }
}
