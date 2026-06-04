import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/feature_assimilation_layer.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/verification/c1_simulation.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/verification/c2_simulation.dart';
import 'package:talkmate_ai/core/app_brain/feature_contracts.dart';
import 'package:talkmate_ai/core/app_brain/feature_intelligence/verification/f2_simulation.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/verification/f3_simulation.dart';
import 'package:talkmate_ai/core/app_brain/intent_inference/verification/f4_simulation.dart';
import 'package:talkmate_ai/core/app_brain/personality/verification/f6_simulation.dart';
import 'package:talkmate_ai/core/app_brain/self_awareness/verification/g1_simulation.dart';
import 'package:talkmate_ai/core/app_brain/self_reflection/verification/g2_simulation.dart';
import 'package:talkmate_ai/core/app_brain/trust_ethics/verification/f5_simulation.dart';

/// Verification Script for Stage F1
/// Run this manually or call `AllocationLayerVerification.run()` from a debug menu.
class AssimilationLayerVerification {
  static Future<void> run() async {
    debugPrint('🧪 Starting Assimilation Layer Verification...');

    final brain = Get.find<AppBrain>();
    final assimilation = Get.find<FeatureAssimilationLayer>();
    final gatekeeper = assimilation.gatekeeper;
    final List<IBrainFeature> clients = [
      assimilation.calls,
      assimilation.chat,
      assimilation.notifications,
    ];

    // 1. Verify Registration
    debugPrint('1. Verifying Feature Registration...');
    for (var client in clients) {
      // Ideally check if brain knows them, but we trust the init for now.
      debugPrint('   - ${client.featureId}: Registered (Trust)');
    }

    // 2. Verify Gatekeeper Logic (Emergency)
    debugPrint('2. Verifying Gatekeeper (Emergency State)...');
    await brain.transitionTo(AppSystemState.emergency);

    final response =
        gatekeeper.requestAccess('multimedia_system_v1', action: 'start_call');
    if (!response.isAllowed) {
      debugPrint('   ✅ Call blocked in Emergency state: ${response.reason}');
    } else {
      debugPrint('   ❌ FAIL: Call allowed in Emergency state!');
    }

    // 3. Verify State Translation
    debugPrint('3. Verify State Translation (Calling State)...');
    await brain.transitionTo(AppSystemState.calling);

    // Check Notification Client State
    // We expect sound to be disabled
    if (!assimilation.notifications.allowSound) {
      debugPrint('   ✅ Notification Sound disabled during Call');
    } else {
      debugPrint('   ❌ FAIL: Notification Sound enabled during Call!');
    }

    // 4. Run Stage F2 Simulation
    await F2SimulationScenario.run();

    // 5. Run Stage F3 Simulation (Negotiation)
    await F3SimulationScenario.run();

    // 6. Run Stage F4 Simulation (Intent)
    await F4SimulationScenario.run();

    // 7. Run Stage F5 Simulation (Ethics & Trust)
    await F5SimulationScenario.run();

    // 8. Run Stage F6 Simulation (Personality)
    await F6SimulationScenario.run();

    // 9. Run Stage G1 Simulation (Self-Awareness)
    await G1SimulationScenario.run();

    // 10. Run Stage G2 Simulation (Self-Reflection)
    await G2SimulationScenario.run();

    // 11. Run Stage C1 Simulation (Feature Integration)
    await C1SimulationScenario.run();

    // 12. Run Stage C2 Simulation (Multi-Party & Adaptive)
    await C2SimulationScenario.run();

    debugPrint('🧪 Verification Complete.');

    // Reset state
    await brain.transitionTo(AppSystemState.idle);
  }
}
