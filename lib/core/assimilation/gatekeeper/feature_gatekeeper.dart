import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../communication/communication_controller.dart';

import '../../predictive/predictive_contracts.dart'; // For BCI
import '../../resilience/degradation_manager.dart';

import '../../self_optimization/adaptive_profiles.dart';
import '../contracts/definitions.dart';
import '../contracts/feature_contracts.dart';
import '../translation/brain_state_translator.dart';

/// FeatureGatekeeper: The Guard at the Door.
///
/// Intercepts every feature request and decides its fate based on the full
/// context of the App Brain (Resilience, Prediction, Optimization).
class FeatureGatekeeper {
  static final FeatureGatekeeper instance = FeatureGatekeeper._();
  FeatureGatekeeper._();

  /// The Registry of known contracts.
  final Map<FeatureType, IFeatureContract> _registry = {};

  void register(IFeatureContract contract) {
    _registry[contract.type] = contract;
    debugPrint('FeatureGatekeeper: Registered contract for ${contract.name}');
  }

  /// The Main Gate: Checks if a feature can run.
  Future<FeatureAccessDecision> requestAccess(FeatureType type) async {
    final contract = _registry[type];
    if (contract == null) {
      debugPrint(
          'FeatureGatekeeper: WARNING - No contract for $type. Allowing default.');
      return FeatureAccessDecision
          .allow; // Default for non-assimilated features
    }

    // 1. Gather Context
    final degradationManager = DegradationManager.instance;
    final adaptiveProfiles = AdaptiveRuntimeProfiles.instance;

    // TODO: Connect real BCI source. Using placeholder for now.
    final brainConfidence = BrainConfidence(85.0, DateTime.now());

    // 2. Translate to Signals
    final signals = BrainStateTranslator.translate(
      brainConfidence: brainConfidence,
      systemHealth: degradationManager.currentState,
      powerMode: adaptiveProfiles.powerMode.value,
      networkProfile: adaptiveProfiles.networkQuality.value,
    );

    // 3. Evaluate Logic

    // Rule A: Critical Failure Block
    if (signals.isNetworkUnstable &&
        contract.requirements.contains(FeatureRequirement.internet)) {
      debugPrint(
          'FeatureGatekeeper: Blocking $type due to Network Instability.');
      return FeatureAccessDecision.block;
    }

    // Rule B: Low Power Degradation
    if (signals.isLowPowerMode &&
        contract.requirements.contains(FeatureRequirement.batteryHeavy)) {
      debugPrint('FeatureGatekeeper: Degrading $type due to Low Power.');
      contract.applyDegradation(signals);
      return FeatureAccessDecision.degrade;
    }

    // Rule D: Concurrency Guard (TalkMate Unification Phase)
    if (type == FeatureType.room || type == FeatureType.call) {
      try {
        final commCtrl = Get.find<CommunicationController>();
        // [Stage R5]: Ensure we don't block on a stale observable
        final currentSession = commCtrl.sessionId.value;
        if (currentSession.isNotEmpty) {
          debugPrint(
              'FeatureGatekeeper: Concurrent Session Blocked ($currentSession).');
          return FeatureAccessDecision.block;
        }
      } catch (e) {
        debugPrint(
            'FeatureGatekeeper: CommController not ready yet, proceeding cautiously.');
      }
    }

    // 4. Default Allow
    contract.restoreNormalOperation();
    return FeatureAccessDecision.allow;
  }
}
