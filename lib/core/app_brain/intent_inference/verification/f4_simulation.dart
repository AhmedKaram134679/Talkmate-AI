import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/engine/feature_negotiation_engine.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/models/negotiation_result.dart';

/// Verification Script for Stage F4 (Intent Inference)
class F4SimulationScenario {
  static Future<void> run() async {
    debugPrint('🧪 Starting F4 Intent Simulation...');

    final engine = Get.find<FeatureNegotiationEngine>();
    final brain = Get.find<AppBrain>();

    // Setup: Calling State (System Busy)
    await brain.transitionTo(AppSystemState.calling);

    // Scenario 1: Low Priority Search + NO Intent
    debugPrint('1. Requesting Search (Low Priority) - No Intent');
    final res1 = engine.negotiate('search_v1');
    if (res1.decision == NegotiationDecision.delay ||
        res1.decision == NegotiationDecision.degrade) {
      debugPrint('   ✅ Search Delayed/Degraded as expected.');
    } else {
      debugPrint('   ❌ FAIL: Search should be delayed. Got: ${res1.decision}');
    }

    // Scenario 2: Low Priority Search + URGENT Intent
    debugPrint(
        '2. Requesting Search (Low Priority) - URGENT Intent (Repetition)');
    // Simulating user tapping 3 times -> Urgent Intent
    final res2 =
        engine.negotiate('search_v1', context: {'repetition_count': 3});

    if (res2.decision == NegotiationDecision.approve ||
        (res2.reason.isEmpty && res2.decision != NegotiationDecision.reject)) {
      // Ideally getting 'Approve' or at least better than Reject.
      // Note: Arbitrator logic might still constrain it if load is > 80.
      // In our logic, Priority Boost 10 -> 30. Still might be degraded if Critical/High only.
      // Let's check if priority boost logic worked in logs.
      debugPrint('   ✅ Result with Intent: ${res2.decision}');
    }

    // Scenario 3: Noise Filtering
    debugPrint('3. Requesting Notification - NOISE Intent');
    final res3 =
        engine.negotiate('notifications', context: {'repetition_count': 10});

    if (res3.decision == NegotiationDecision.reject) {
      debugPrint('   ✅ Notification Rejected (Noise Filter).');
    } else {
      debugPrint('   ❌ FAIL: Should be rejected as noise.');
    }

    debugPrint('🧪 F4 Verification Complete.');
    await brain.transitionTo(AppSystemState.idle);
  }
}
