import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/app_brain.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/clients/call_feature_client.dart';

/// Verification Script for Stage C1 (Call Feature Integration)
class C1SimulationScenario {
  static Future<void> run() async {
    debugPrint('📞 Starting C1 Call Feature Simulation...');

    final callClient = Get.find<CallFeatureClient>();
    final brain = Get.find<AppBrain>();

    // Scenario 1: Normal Call (Should Succeed)
    debugPrint('1. 🟢 Attempting Normal Call...');
    await brain.transitionTo(AppSystemState.idle);
    final bool success =
        await callClient.startCall('session_001', ['user_123']);
    if (success) {
      debugPrint('   ✅ Call Allowed.');
      await callClient.endCall(true, 1.0); // Perfect call
    } else {
      debugPrint('   ❌ FAIL: Normal call blocked.');
    }

    // Scenario 2: User Rejection Loop (Behavioral Optimization)
    debugPrint('3. 🛑 Simulating Annoying Call (Rejection Loop)...');

    // Call 1
    await callClient.startCall('spammer_session', ['spammer']);
    // User hates it immediately
    await callClient.endCall(false, 0.0); // Rejected, score 0

    // Call 2 (Should ideally be blocked or warned)
    await callClient.startCall('spammer_session_2', ['spammer_again']);
    await callClient.endCall(false, 0.0);

    debugPrint('🧪 C1 Verification Complete.');
  }
}
