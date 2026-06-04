import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../app_brain.dart';
import '../feature_assimilation_layer.dart';

class C2SimulationScenario {
  static Future<void> run() async {
    debugPrint(
        '🚀 Starting Stage C2 Simulation: Advanced Multi-Party Intelligence');

    final brain = Get.find<AppBrain>();
    final assimilation = Get.find<FeatureAssimilationLayer>();
    final callClient = assimilation.calls;

    // 1. Start a Group Call
    debugPrint('\n--- Scenario 1: Initiating Group Call (3 Participants) ---');
    await brain.transitionTo(AppSystemState.calling);

    final success =
        await callClient.startCall('group_001', ['user_a', 'user_b', 'user_c']);

    if (success) {
      debugPrint('✅ Group Call Started Successfully.');
    } else {
      debugPrint('❌ FAIL: Group Call Blocked.');
      return;
    }

    // 2. Cross-Feature Verification
    debugPrint(
        '\n--- Scenario 2: Verifying Cross-Feature Constraints (Chat/Notification) ---');
    // Brain should have restricted chat and notifications because we are in 'calling' state
    // Note: assimilation._onSystemStateChanged is called by the listener during transitionTo

    if (!assimilation.notifications.allowSound) {
      debugPrint('✅ Brain restricted Notification sound during Call.');
    } else {
      debugPrint('❌ FAIL: Notifications still have sound!');
    }

    // 3. Adaptive Quality: Resource Shift (Network Drop)
    debugPrint(
        '\n--- Scenario 3: Resource Shift (Network Quality 0.8 -> 0.2) ---');
    callClient.simulateResourceShift(0.2, 0.9);

    // Check if participants degraded to audio only
    // In our mock, low network forces audioOnly
    /* 
    if (callClient.supportsVideo) {
       debugPrint('❌ FAIL: System still supports video on poor network!');
    } else {
       debugPrint('✅ System adapted: Video disabled for all due to poor network.');
    }
    */

    // 4. Adaptive Quality: High Interaction Group (Scaling)
    debugPrint('\n--- Scenario 4: Large Group Scaling (6 Participants) ---');
    await callClient
        .startCall('group_002', ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
    // CallQualityOptimizer should favor lower quality for large groups

    // 5. Cleanup
    debugPrint('\n--- Ending C2 Simulation ---');
    await callClient.endCall(true, 1.0);
    await brain.transitionTo(AppSystemState.idle);
  }
}
