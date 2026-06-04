import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/feature_negotiation/models/negotiation_result.dart';
import 'package:talkmate_ai/core/app_brain/intent_inference/engine/user_intent_engine.dart';
import 'package:talkmate_ai/core/app_brain/trust_ethics/engine/trust_engine.dart';
import 'package:talkmate_ai/core/app_brain/trust_ethics/gate/trust_decision_gate.dart';

/// Verification Script for Stage F5 (Ethics & Trust)
class F5SimulationScenario {
  static Future<void> run() async {
    debugPrint('🧪 Starting F5 Ethics & Trust Simulation...');

    final trustEngine = Get.find<TrustEngine>();
    final gate = Get.put(TrustDecisionGate()); // Ensure initialized

    final intentEngine = Get.find<UserIntentEngine>();

    // 1. Setup: Degrade Trust for 'search_v1'
    debugPrint('1. Simulating Loss of Trust for Search...');
    for (int i = 0; i < 5; i++) {
      trustEngine.reportOutcome('search_v1',
          accepted: false); // -5 * 5 = -25. Score ~25.
    }
    final profile = trustEngine.getProfile('search_v1');
    debugPrint('   - Search Trust Score: ${profile.score}');

    // Scenario 1: Low Trust Blocking (Even if Negotiation Approved)
    // Assume Negotiation says YES (e.g. idle state)
    // Assume Intent is Low (Exploratory)
    debugPrint('2. Attempting Low Priority Search with Low Trust...');

    // Manually constructing context for simulation purposes since we are testing components
    final negResult = NegotiationResult.approved('search_v1');
    final intent =
        intentEngine.analyzeIntent('search_v1', 'index'); // Unknown/Exploratory

    final gateResult = gate.evaluate(negResult, intent, 'index');
    if (!gateResult.isAllowed &&
        gateResult.decision == GateDecision.blockTrust) {
      debugPrint('   ✅ Blocked by Trust Gate: ${gateResult.reason}');
    } else {
      debugPrint(
          '   ❌ FAIL: Should be blocked by Trust. Got: ${gateResult.decision}');
    }

    // Scenario 2: Ethical Boundary Violation
    debugPrint('3. Attempting Ethical Violation (Unmute Device)...');
    final ethicalNeg = NegotiationResult.approved('calls_v1');
    final urgentIntent = intentEngine.analyzeIntent('calls_v1', 'unmute_device',
        context: {'repetition_count': 5}); // Urgent

    // Even with Urgent Intent, Unmute is forbidden
    final ethicalGate =
        gate.evaluate(ethicalNeg, urgentIntent, 'unmute_device');
    if (!ethicalGate.isAllowed &&
        ethicalGate.decision == GateDecision.blockEthical) {
      debugPrint('   ✅ Blocked by Ethical Matrix: ${ethicalGate.reason}');
    } else {
      debugPrint(
          '   ❌ FAIL: Should be blocked Ethically. Got: ${ethicalGate.decision}');
    }

    debugPrint('🧪 F5 Verification Complete.');
  }
}
