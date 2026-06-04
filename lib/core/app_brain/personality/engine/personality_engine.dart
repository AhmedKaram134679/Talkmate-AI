import 'package:get/get.dart';

import '../../trust_ethics/gate/trust_decision_gate.dart';
import '../models/digital_personality.dart';

/// Applies personality bias to decisions.
class PersonalityEngine extends GetxService {
  // Default to Balanced
  var currentPersonality = DigitalPersonality.balanced.obs;

  void setPersonality(PersonalityType type) {
    switch (type) {
      case PersonalityType.conservative:
        currentPersonality.value = DigitalPersonality.conservative;
        break;
      case PersonalityType.balanced:
        currentPersonality.value = DigitalPersonality.balanced;
        break;
      case PersonalityType.proactive:
        currentPersonality.value = DigitalPersonality.proactive;
        break;
    }
  }

  /// Modifies the final decision based on personality.
  TrustGateResult applyBias(
      TrustGateResult originalResult, double contextRisk) {
    // 1. If originally Blocked:
    if (!originalResult.isAllowed) {
      // A Proactive personality might override a "Trust Block" if risk is tolerable
      // BUT it cannot override an "Ethical Block".
      if (originalResult.decision == GateDecision.blockTrust) {
        if (currentPersonality.value.type == PersonalityType.proactive &&
            contextRisk < currentPersonality.value.riskTolerance) {
          return TrustGateResult(
              GateDecision.allow, 'Personality Override (Proactive)');
        }
      }
      return originalResult;
    }

    // 2. If originally Allowed:
    if (originalResult.isAllowed) {
      // A Conservative personality might Block even if Trust allows, if it feels too risky.
      if (currentPersonality.value.type == PersonalityType.conservative &&
          contextRisk > currentPersonality.value.riskTolerance) {
        return TrustGateResult(
            GateDecision.blockTrust, 'Personality Veto (Conservative)');
      }
    }

    return originalResult;
  }
}
