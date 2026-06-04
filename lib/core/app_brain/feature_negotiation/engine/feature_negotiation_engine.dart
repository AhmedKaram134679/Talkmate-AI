import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../app_brain.dart';
import '../../intent_inference/engine/user_intent_engine.dart';
import '../../intent_inference/models/intent_hypothesis.dart';
import '../arbitration/priority_arbitrator.dart';
import '../models/feature_priority_profile.dart';
import '../models/negotiation_request.dart';
import '../models/negotiation_result.dart';

/// Service that coordinates the negotiation process.
class FeatureNegotiationEngine extends GetxService {
  final PriorityArbitrator _arbitrator = PriorityArbitrator();

  final _intentEngine = Get.put(UserIntentEngine());
  final AppBrain _brain = Get.find<AppBrain>();

  // Registry of Profiles (Config)
  final Map<String, FeaturePriorityProfile> _profiles = {
    'calls_v1': FeaturePriorityProfile.critical,
    'chat_v1': FeaturePriorityProfile.high,
    'notifications': FeaturePriorityProfile.normal,
    'search_v1': FeaturePriorityProfile.background,
  };

  // State
  final List<NegotiationResult> _activeFeatures = [];

  /// Called by Assimilation Layer when a feature wants to act.
  NegotiationResult negotiate(String featureId,
      {String action = 'execute', Map<String, dynamic> context = const {}}) {
    final profile = _profiles[featureId] ?? FeaturePriorityProfile.normal;
    final request = NegotiationRequest(featureId: featureId, action: action);

    // 1. Get Context (FIS & System Load & Intent)
    final int systemLoad = _brain.state.value == AppSystemState.calling ? 85 : 10;

    // Stage F4: Infer Intent
    final intent =
        _intentEngine.analyzeIntent(featureId, action, context: context);
    debugPrint('🧠 Intent: ${intent.toString()}');

    // 2. Pre-Arbitration: Intent Filtering
    if (intent.type == IntentType.noise && intent.confidence > 0.8) {
      return NegotiationResult.rejected(featureId, 'Noise Detected');
    }

    // 3. Arbitrate
    // We boost priority if Intent is Urgent and Confidence is high
    final effectiveProfile =
        (intent.type == IntentType.urgent && intent.confidence > 0.7)
            ? FeaturePriorityProfile(
                basePriority: profile.basePriority + 20, // Boost!
                isCritical: profile.isCritical,
                userSensitivity: profile.userSensitivity)
            : profile;

    final result = _arbitrator.arbitrate(
        request, effectiveProfile, systemLoad, _activeFeatures);

    debugPrint(
        '⚖️ Negotiation: $featureId requested -> ${result.decision.name} (Load: $systemLoad, IntentBoost: ${effectiveProfile.basePriority != profile.basePriority})');

    // 4. Track Active Features (simplified)
    if (result.decision == NegotiationDecision.approve ||
        result.decision == NegotiationDecision.degrade) {
      _updateActiveFeatures(result);
    }

    return result;
  }

  void _updateActiveFeatures(NegotiationResult result) {
    // Remove existing entry for this feature
    _activeFeatures.removeWhere((r) => r.featureId == result.featureId);
    // Add new
    _activeFeatures.add(result);
  }
}
