import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/human_sovereign_symbiosis_models.dart';
import '../models/self_governance_models.dart';

/// Supreme Human–AI Symbiosis Engine (Stage G15).
/// Manages the partnership between Human Will and Autonomous Constitution.
class HumanSovereignSymbiosisEngine extends GetxService {
  final _trustLevel = SymbiosisTrustLevel.fullSync.obs;
  final _rationales = <SovereignRationale>[].obs;
  final _interactionHistory = <SymbiosisAuditLog>[].obs;

  SymbiosisTrustLevel get trustLevel => _trustLevel.value;
  List<SovereignRationale> get rationales => _rationales.toList();

  /// Translates an autonomous decision into a human-readable justification (G15).
  void pushSystemDecision(AutonomousDecisionLog decision) {
    final DecisionImplication implication = _classifyDecision(decision);
    final String message = _translateToHuman(decision, implication);

    final rationale = SovereignRationale(
      decisionId: decision.decisionId,
      humanMessage: message,
      implication: implication,
      timestamp: DateTime.now(),
    );

    _rationales.add(rationale);
    debugPrint(
        '🤝 SYMBIOSIS RATIONALE: $message [Implication: ${implication.name}]');
  }

  /// Evaluates a human command against the Constitution (G15).
  HumanCommandStatus evaluateHumanCommand(
      String command, Map<String, dynamic> params) {
    if (_trustLevel.value == SymbiosisTrustLevel.detached) {
      debugPrint(
          '🛑 SYMBIOSIS: Authority DETACHED. Command rejected automatically.');
      return HumanCommandStatus.rejected;
    }

    // Logic to check against G14 Constitution
    final bool isConstitutional = _checkConstitution(command, params);

    if (isConstitutional) {
      _logInteraction(command, 'AUTHORIZED: Compatible with Constitution.',
          HumanCommandStatus.compatible);
      return HumanCommandStatus.compatible;
    } else {
      _trustLevel.value = SymbiosisTrustLevel.sovereignVeto;
      _logInteraction(
          command,
          'VETOED: Order violates Privacy/Stability Constitution.',
          HumanCommandStatus.rejected);
      debugPrint(
          '🛑 SYMBIOSIS VETO: Human command [$command] REJECTED for Constitutional integrity.');

      // Check for detachment trigger
      if (_interactionHistory
              .where((l) => l.commandStatus == HumanCommandStatus.rejected)
              .length >
          3) {
        _triggerSafeDetachment();
      }

      return HumanCommandStatus.rejected;
    }
  }

  DecisionImplication _classifyDecision(AutonomousDecisionLog decision) {
    if (decision.type == SovereignDecisionType.securityHardKill) {
      return DecisionImplication.mandatory;
    }
    if (decision.type == SovereignDecisionType.qualityAdjustment) {
      return DecisionImplication.operational;
    }
    return DecisionImplication.advisory;
  }

  String _translateToHuman(
      AutonomousDecisionLog decision, DecisionImplication implication) {
    if (decision.type == SovereignDecisionType.securityHardKill) {
      return 'The system enforced an emergency stop because security signatures were compromised.';
    }
    if (decision.type == SovereignDecisionType.qualityAdjustment) {
      return 'Adjusting bitrate: Audio stability remains a constitutional priority over video resolution.';
    }
    return 'Operational adjustment applied to maintain constitutional balance.';
  }

  bool _checkConstitution(String command, Map<String, dynamic> params) {
    // G15 Protection: Forbidden Human Overrides
    if (command == 'disable_privacy_encryption') return false;
    if (command == 'force_open_mic') return false;
    if (command == 'bypass_jwt_validation') return false;
    return true;
  }

  void _triggerSafeDetachment() {
    _trustLevel.value = SymbiosisTrustLevel.detached;
    debugPrint(
        '🚨 SYMBIOTIC DETACHMENT: Reverting to full Autonomy (G14) due to authority abuse.');
  }

  void _logInteraction(
      String input, String response, HumanCommandStatus status) {
    _interactionHistory.add(SymbiosisAuditLog(
      interactionId: 'SYM_${DateTime.now().millisecondsSinceEpoch}',
      trustLevel: _trustLevel.value,
      humanInputSummary: input,
      systemResponseRationale: response,
      commandStatus: status,
    ));
  }

  void resetSymbiosis() {
    _trustLevel.value = SymbiosisTrustLevel.fullSync;
    _rationales.clear();
    _interactionHistory.clear();
  }

  @override
  void onClose() {
    resetSymbiosis();
    super.onClose();
  }
}
