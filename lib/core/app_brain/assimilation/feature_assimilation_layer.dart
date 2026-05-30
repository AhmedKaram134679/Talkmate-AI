import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/feature_contracts.dart';
import 'package:talkmate_ai/core/app_brain/self_reflection/models/decision_outcome.dart';

import '../app_brain.dart';
import '../feature_intelligence/engine/adaptive_policy_engine.dart';
import '../feature_negotiation/engine/feature_negotiation_engine.dart';
import '../feature_negotiation/models/negotiation_result.dart';
import '../intent_inference/engine/user_intent_engine.dart';
import '../personality/alignment/long_term_alignment_engine.dart';
import '../personality/engine/personality_engine.dart';
import '../self_awareness/engine/self_explanation_engine.dart';
import '../self_awareness/memory/decision_memory_store.dart';
import '../self_awareness/metrics/decision_confidence_index.dart';
import '../self_awareness/models/decision_trace.dart';
import '../self_reflection/engine/behavior_optimization_engine.dart';
import '../self_reflection/engine/self_reflection_engine.dart';
import '../trust_ethics/engine/trust_engine.dart';
import '../trust_ethics/gate/trust_decision_gate.dart';
import 'clients/call_feature_client.dart';
import 'clients/chat_feature_client.dart';
import 'clients/notification_feature_client.dart';
import 'clients/search_feature_client.dart';
import 'feature_gatekeeper.dart';
import 'models/assimilation_result.dart';

// IAssimilatedClient removed, using IBrainFeature instead.

class FeatureAssimilationLayer extends GetxService {
  final _brain = Get.find<AppBrain>();
  final _gatekeeper = Get.put(FeatureGatekeeper());
  final _policyEngine = Get.put(AdaptivePolicyEngine());
  final _negotiationEngine = Get.put(FeatureNegotiationEngine());
  final _trustGate = Get.put(TrustDecisionGate());
  final _personalityEngine = Get.put(PersonalityEngine());
  final _alignmentEngine = Get.put(LongTermAlignmentEngine());
  final _memoryStore = Get.put(DecisionMemoryStore());
  final _explainer = Get.put(SelfExplanationEngine());
  final _reflectionEngine = Get.put(SelfReflectionEngine());
  late final BehaviorOptimizationEngine
      _optimizer; // Lazy init to ensure reflection is ready

  // Clients
  late final CallFeatureClient calls;
  late final ChatFeatureClient chat;
  late final NotificationFeatureClient notifications;
  late final SearchFeatureClient search;
  late final UserIntentEngine _intentEngine;
  late final TrustEngine _trustEngine;

  Future<void> init() async {
    debugPrint('FeatureAssimilationLayer: Initializing Intelligent Clients...');

    // 0. Init Optimizer
    _optimizer = Get.put(BehaviorOptimizationEngine());

    // 1. Initialize Clients
    calls = Get.put(CallFeatureClient());
    chat = Get.put(ChatFeatureClient());
    notifications = Get.put(NotificationFeatureClient());
    search = Get.put(SearchFeatureClient());
    _intentEngine = Get.put(UserIntentEngine());
    _trustEngine = Get.put(TrustEngine());

    // 2. Boot Clients
    await Future.wait([
      calls.boot(),
      chat.boot(),
      notifications.boot(),
      search.boot(),
    ]);

    // 3. Register with Brain
    _brain.registerFeature(calls.featureId);
    _brain.registerFeature(chat.featureId);
    _brain.registerFeature(notifications.featureId);
    _brain.registerFeature(search.featureId);

    // 4. Start Monitoring Brain State
    _brain.state.listen(_onSystemStateChanged);

    debugPrint('FeatureAssimilationLayer: All systems operational.');
  }

  /// React to system state changes by distributing constraints.
  void _onSystemStateChanged(AppSystemState newState) {
    debugPrint('FeatureAssimilationLayer: System State Change -> $newState');

    _applyConstraints(calls, newState);
    _applyConstraints(chat, newState);
    _applyConstraints(notifications, newState);
    _applyConstraints(search, newState);
  }

  /// Public API for Features to request access to resources or actions.
  /// Runs the full G1/G2/C1 decision pipeline.
  AssimilationResult requestAccess(String featureId,
      {required String action, Map<String, dynamic> context = const {}}) {
    try {
      // 0. Negotiate Priority (Stage F3)
      final negotiation = _negotiationEngine.negotiate(featureId);

      // Stage F4: Infer Intent
      final intent = _intentEngine.analyzeIntent(featureId, action);

      // Stage G2: Behavior Optimization
      final riskModifier =
          _optimizer.getRiskAdjustment(featureId, 'Proactive_HighRisk');

      // Stage F5: Trust & Ethics Gate
      var gateResult = _trustGate.evaluate(negotiation, intent, action);

      // Stage F6: Personality Bias
      final double rawRisk = 0.6; // Mock risk for now
      final double effectiveRisk = rawRisk / riskModifier;
      gateResult = _personalityEngine.applyBias(gateResult, effectiveRisk);

      // Stage F6: Long-Term Alignment
      gateResult = _alignmentEngine.checkAlignment(gateResult, featureId);

      // Stage G1: Self-Awareness (Traceability)
      final trace = DecisionTrace(
          featureId: featureId,
          action: action,
          finalDecision: gateResult.decision,
          reason: gateResult.reason,
          trustScore: _trustEngine.getProfile(featureId).score,
          personality: _personalityEngine.currentPersonality.value.type,
          riskLevel: effectiveRisk,
          alignedWithHistory: true);

      // Store Trace
      _memoryStore.addTrace(trace);

      // Explain & Confidence
      final explanation = _explainer.explain(trace);
      final confidence = DecisionConfidenceIndex.calculate(trace);

      debugPrint(
          'The Brain: $explanation [Confidence: ${(confidence * 100).toStringAsFixed(0)}%]');

      // Calculate Final Constraints
      final constraints = <String, dynamic>{};
      if (gateResult.isAllowed) {
        constraints
            .addAll(_policyEngine.resolvePolicy(_brain.state.value, featureId));
      }

      // Cross-Feature Constraints
      if (_brain.state.value == AppSystemState.calling) {
        if (featureId == chat.featureId) {
          constraints['enabled'] = false;
        } else if (featureId == notifications.featureId) {
          constraints['sound'] = false;
        }
      }

      // Merge Negotiation constraints
      if (negotiation.decision == NegotiationDecision.degrade) {
        constraints.addAll(negotiation.finalConstraints);
      }

      if (negotiation.decision == NegotiationDecision.reject ||
          !gateResult.isAllowed) {
        constraints['enabled'] = false;
      }

      return AssimilationResult(
        isAllowed: gateResult.isAllowed &&
            negotiation.decision != NegotiationDecision.reject,
        decision: gateResult.isAllowed
            ? negotiation.decision
            : NegotiationDecision.reject,
        constraints: constraints,
        trace: trace,
        reason: gateResult.reason,
      );
    } catch (e) {
      debugPrint('🧠 Brain Crash! Critical error in requestAccess: $e');
      // Emergency Fallback: Allow with strict constraints or reject depending on safety profile.
      // For now, we reject to be safe (Fail-Safe).
      return AssimilationResult(
        isAllowed: false,
        decision: NegotiationDecision.reject,
        constraints: {'enabled': false},
        trace: null,
        reason: 'Internal Brain Error',
      );
    }
  }

  void _applyConstraints(IBrainFeature client, AppSystemState state) {
    // We treat state updates as a request to 'maintain_state' or 'adapt'.
    final result = requestAccess(client.featureId, action: 'adapt_to_state');

    if (!result.isAllowed) {
      debugPrint(
          '🛡️ Assimilation: ${client.featureId} Blocked/Disabled by Brain.');
      client.applyPolicy({'enabled': false});
      return;
    }

    if (result.constraints.isNotEmpty) {
      client.applyPolicy(result.constraints);
    }
  }

  // Experimental: Expose Gatekeeper for external usage
  FeatureGatekeeper get gatekeeper => _gatekeeper;

  /// Feedback Loop: Report the outcome of a decision to learn from it.
  void reportOutcome(
      String featureId, OutcomeStatus status, double satisfaction) {
    // 1. Find the last trace for this feature
    // In a real app, we'd look up by specific transaction ID.
    // Here we just grab the last one from memory for this feature.
    final List<DecisionTrace> traces =
        _memoryStore.getRecentTraces().cast<DecisionTrace>();
    final lastTrace = traces.lastWhereOrNull((t) => t.featureId == featureId);

    if (lastTrace != null) {
      final outcome = DecisionOutcome(
          trace: lastTrace, status: status, satisfactionScore: satisfaction);

      _reflectionEngine.processOutcome(outcome);
    }
  }
}
