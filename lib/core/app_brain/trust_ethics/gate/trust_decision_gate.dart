import 'package:get/get.dart';

import '../../feature_negotiation/models/negotiation_result.dart';
import '../../intent_inference/models/intent_hypothesis.dart';
import '../engine/trust_engine.dart';
import '../ethics/ethical_boundary_matrix.dart';

enum GateDecision {
  allow,
  blockEthical,
  blockTrust,
}

class TrustGateResult {
  final GateDecision decision;
  final String reason;

  TrustGateResult(this.decision, [this.reason = '']);

  bool get isAllowed => decision == GateDecision.allow;
}

class TrustDecisionGate extends GetxService {
  final _trustEngine = Get.put(TrustEngine());

  TrustGateResult evaluate(
      NegotiationResult negotiation, IntentHypothesis intent, String action) {
    try {
      final profile = _trustEngine.getProfile(negotiation.featureId);

      // 1. Check Ethical Boundaries (The Hard Line)
      if (!EthicalBoundaryMatrix.isEthicallyAllowed(action, profile.score)) {
        return TrustGateResult(
            GateDecision.blockEthical, 'Ethical Boundary Violation');
      }

      // 2. Check Trust vs Intent
      // If Intent is URGENT, we lower the Trust barrier slightly
      double requiredTrust = 40.0;

      if (intent.type == IntentType.urgent) {
        requiredTrust = 30.0; // Allow a bit more leeway if urgent
      } else if (intent.type == IntentType.noise) {
        requiredTrust = 80.0; // High barrier for noise
      }

      if (profile.score < requiredTrust) {
        return TrustGateResult(GateDecision.blockTrust,
            'Insufficient Trust (${profile.score.toStringAsFixed(1)} < $requiredTrust)');
      }

      return TrustGateResult(GateDecision.allow);
    } catch (e) {
      return TrustGateResult(
          GateDecision.blockTrust, 'Internal evaluating error: $e');
    }
  }
}
