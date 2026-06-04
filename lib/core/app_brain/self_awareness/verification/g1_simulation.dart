import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:talkmate_ai/core/app_brain/personality/models/digital_personality.dart';
import 'package:talkmate_ai/core/app_brain/self_awareness/engine/self_explanation_engine.dart';
import 'package:talkmate_ai/core/app_brain/self_awareness/memory/decision_memory_store.dart';
import 'package:talkmate_ai/core/app_brain/self_awareness/models/decision_trace.dart';
import 'package:talkmate_ai/core/app_brain/trust_ethics/gate/trust_decision_gate.dart';

/// Verification Script for Stage G1 (Self-Awareness)
class G1SimulationScenario {
  static Future<void> run() async {
    debugPrint('🧪 Starting G1 Self-Awareness Simulation...');

    final memory = Get.find<DecisionMemoryStore>();
    final explainer = Get.find<SelfExplanationEngine>();

    // Simulate a Decision Trace manually to test the engine
    final mockTrace = DecisionTrace(
        featureId: 'calls_v1',
        action: 'start_call',
        finalDecision: GateDecision.allow,
        reason: 'Personality Override (Proactive)',
        trustScore: 40.0,
        personality: PersonalityType.proactive,
        riskLevel: 0.15,
        alignedWithHistory: true);

    // 1. Test Memory Storage
    memory.addTrace(mockTrace);
    final traces = memory.getRecentTraces();
    if (traces.isNotEmpty && traces.last == mockTrace) {
      debugPrint('   ✅ Memory Store correctly recorded the trace.');
    } else {
      debugPrint('   ❌ FAIL: Trace not found in memory.');
    }

    // 2. Test Explanation Engine
    final explanation = explainer.explain(mockTrace);
    debugPrint('   📝 Generated Explanation: "$explanation"');

    if (explanation.contains('proactive personality encourages taking risks')) {
      debugPrint('   ✅ Explanation correctly identified the "Why".');
    } else {
      debugPrint('   ❌ FAIL: Explanation logic seems off.');
    }

    debugPrint('🧪 G1 Verification Complete.');
  }
}
