import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/personality/engine/personality_engine.dart';
import 'package:talkmate_ai/core/app_brain/personality/models/digital_personality.dart';
import 'package:talkmate_ai/core/app_brain/trust_ethics/gate/trust_decision_gate.dart';

/// Verification Script for Stage F6 (Personality & Alignment)
class F6SimulationScenario {
  static Future<void> run() async {
    debugPrint('🧪 Starting F6 Personality & Alignment Simulation...');

    final personalityEngine = Get.find<PersonalityEngine>();

    // Scenario 1: Conservative Personality blocks Risky Action
    debugPrint('1. Setting Personality to Conservative...');
    personalityEngine.setPersonality(PersonalityType.conservative);

    // Simulate a Trust Gate ALLOW result, but with High Risk (0.7)
    // Conservative tolerance is 0.2
    final allowedResult =
        TrustGateResult(GateDecision.allow, 'Trust Sufficient');
    final finalResult = personalityEngine.applyBias(allowedResult, 0.7);

    if (!finalResult.isAllowed &&
        finalResult.reason.contains('Personality Veto')) {
      debugPrint('   ✅ Conservative Personality Vetoed High Risk Action.');
    } else {
      debugPrint(
          '   ❌ FAIL: Conservative should veto High Risk. Got: ${finalResult.decision}');
    }

    // Scenario 2: Proactive Personality overrides Trust Block
    debugPrint('2. Setting Personality to Proactive...');
    personalityEngine.setPersonality(PersonalityType.proactive);

    // Simulate a Trust Gate BLOCK result
    // Proactive tolerance is 0.8. Risk is Low (0.1)
    final blockedResult =
        TrustGateResult(GateDecision.blockTrust, 'Not enough trust');
    final proactiveResult = personalityEngine.applyBias(blockedResult, 0.1);

    if (proactiveResult.isAllowed &&
        proactiveResult.reason.contains('Personality Override')) {
      debugPrint(
          '   ✅ Proactive Personality Overrode Trust Block for Low Risk.');
    } else {
      debugPrint(
          '   ❌ FAIL: Proactive should override. Got: ${proactiveResult.decision}');
    }

    debugPrint('🧪 F6 Verification Complete.');
  }
}
