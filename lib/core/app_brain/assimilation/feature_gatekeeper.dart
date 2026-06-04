import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/release/feature_flag_provider.dart';
import 'package:talkmate_ai/core/release/release_models.dart';

import '../adaptive/adaptive_controller.dart';
import '../adaptive/adaptive_models.dart';
import '../app_brain.dart';
import '../engagement/engagement_engine.dart';

/// Response from the Gatekeeper when a feature requests access.
class GatekeeperResponse {
  final bool isAllowed;
  final String? reason;
  final Map<String, dynamic> constraints;

  GatekeeperResponse({
    required this.isAllowed,
    this.reason,
    this.constraints = const {},
  });

  factory GatekeeperResponse.allowed(
      [Map<String, dynamic> constraints = const {}]) {
    return GatekeeperResponse(isAllowed: true, constraints: constraints);
  }

  factory GatekeeperResponse.denied(String reason) {
    return GatekeeperResponse(isAllowed: false, reason: reason);
  }
}

/// The Gatekeeper stands between User Actions and Feature Execution.
/// It consults the AppBrain and EngagementEngine to decide if an action is allowed.
class FeatureGatekeeper extends GetxService {
  final IAppBrain _brain = Get.find<AppBrain>();
  // ignore: unused_field
  final EngagementEngine? _engagementEngine; // Reserved for complex rules

  FeatureGatekeeper({EngagementEngine? engagementEngine})
      : _engagementEngine = engagementEngine;

  /// Check if a specific feature type can execute in the current state.
  GatekeeperResponse requestAccess(String featureId, {String? action}) {
    final currentState = _brain.state.value;

    debugPrint(
        'Gatekeeper: Checking access for $featureId ($action) in state $currentState');

    // 1. Critical System States (Emergency / Kill Switch)
    if (currentState == AppSystemState.emergency) {
      return GatekeeperResponse.denied('System in Emergency state');
    }

    // 2. State-Based Rules
    switch (currentState) {
      case AppSystemState.calling:
        // Blocks distractions during calls
        if (featureId == 'notifications') {
          return GatekeeperResponse.allowed({'silent': true});
        }
        if (featureId == 'multimedia_system_v1') {
          // Block starting a NEW call if already in one (unless multi-call implemented)
          if (action == 'start_call') {
            return GatekeeperResponse.denied('Already in a call');
          }
        }
        break;

      case AppSystemState.background:
        if (featureId == 'multimedia_system_v1' && action == 'video') {
          return GatekeeperResponse.denied('Video not allowed in background');
        }
        break;

      case AppSystemState.idle:
      case AppSystemState.chatting:
      default:
        break;
    }

    // 3. Dynamic Feature Flags (Stage D5)
    final flags = FeatureFlagProvider.instance;
    final featureState = flags.getFeatureState(featureId);

    if (featureState == FeatureState.disabled ||
        featureState == FeatureState.hardKill) {
      return GatekeeperResponse.denied(
          'Feature $featureId is disabled by Production Flags');
    }

    // 4. Adaptive Intelligence Overrides
    final adaptive = AdaptiveController.instance;
    if (adaptive.currentLevel == PerformanceLevel.critical) {
      // Auto-restrict bandwidth or resource heavy features
      if (featureId == 'multimedia_system_v1' ||
          featureId == 'high_res_media') {
        return GatekeeperResponse.denied(
            'System resource critical: Adaptation active');
      }
    }

    // Apply adjustments from the engine (Degradation)
    final finalConstraints = <String, dynamic>{};
    if (adaptive.adjustments.isNotEmpty) {
      finalConstraints.addAll(adaptive.adjustments);
    }

    // Default: Allow with adaptive constraints
    return GatekeeperResponse.allowed(finalConstraints);
  }
}
