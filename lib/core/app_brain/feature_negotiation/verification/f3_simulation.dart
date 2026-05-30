import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/engine/feature_negotiation_engine.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/models/negotiation_result.dart';

/// Verification Script for Stage F3 (Negotiation)
class F3SimulationScenario {
  static Future<void> run() async {
    debugPrint('🧪 Starting F3 Negotiation Simulation...');

    final engine = Get.find<FeatureNegotiationEngine>();
    final brain = Get.find<AppBrain>();

    // 1. Setup Context: Calling State (High Load)
    debugPrint('1. Setting System State to Calling (Simulating High Load)...');
    await brain.transitionTo(AppSystemState.calling);

    // Calls are critical, so they should be running.
    engine.negotiate('calls_v1', action: 'active_call');

    // 2. Conflict: Notification vs Call
    debugPrint('2. Requesting Notification during Call...');
    final notifResult = engine.negotiate('notifications', action: 'show');

    debugPrint('   - Result: ${notifResult.toString()}');
    if (notifResult.decision == NegotiationDecision.degrade) {
      debugPrint('   ✅ Notification Degraded (Priority 40 vs 90)');
    } else {
      debugPrint('   ❌ FAIL: Notification should be degraded');
    }

    // 3. Conflict: Search (Background) vs Call
    debugPrint('3. Requesting Search during Call...');
    final searchResult = engine.negotiate('search_v1', action: 'index');

    debugPrint('   - Result: ${searchResult.toString()}');
    // Expect Delay or Degrade
    if (searchResult.decision == NegotiationDecision.delay ||
        searchResult.decision == NegotiationDecision.degrade) {
      debugPrint('   ✅ Search Delayed/Degraded (Priority 10 vs 90)');
    } else {
      debugPrint('   ❌ FAIL: Search should be delayed');
    }

    debugPrint('🧪 F3 Verification Complete.');
    await brain.transitionTo(AppSystemState.idle);
  }
}
