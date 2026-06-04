import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/self_governance_models.dart';
import '../models/sovereign_analytics_models.dart';

/// Sovereign Self-Governance Engine (Stage G14).
/// The autonomous brain of TalkMate AI that enforces the Constitution.
class SelfGovernanceEngine extends GetxService {
  final _decisionHistory = <AutonomousDecisionLog>[].obs;
  final _isAutonomousMode = true.obs;
  final _lastDecision = Rxn<AutonomousDecisionLog>();

  List<AutonomousDecisionLog> get decisionHistory => _decisionHistory.toList();
  Stream<AutonomousDecisionLog?> get decisionStream => _lastDecision.stream;

  /// Processes technical signals and takes autonomous actions (G14).
  void evaluateGovernance(List<SovereignDataPoint> recentMetrics) {
    if (!_isAutonomousMode.value) return;

    for (var metric in recentMetrics) {
      // 1. Check for Imminent Security/Stability Threat (Hard Kill Trigger)
      if (metric.type == AnalyticsMetricType.packetLoss &&
          metric.value >= ConstitutionalThresholds.packetLossKill) {
        _takeDecision(
          SovereignDecisionType.securityHardKill,
          'Critical Packet Loss (${metric.value}%) violates Stability Sanctity.',
          {'force_kill': true},
        );
      }

      // 2. Check for Resource Pressure (Degradation Trigger)
      if (metric.type == AnalyticsMetricType.cpuPressure &&
          metric.value >= ConstitutionalThresholds.cpuPressureDegrade) {
        _takeDecision(
          SovereignDecisionType.qualityAdjustment,
          'High CPU Usage (${metric.value}%) requires Resource Balancing.',
          {'low_bitrate': true, 'disable_ai': true},
        );
      }
    }
  }

  void _takeDecision(SovereignDecisionType type, String rationale,
      Map<String, dynamic> constraints) {
    final decision = AutonomousDecisionLog(
      decisionId: 'AUTO_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      rationale: rationale,
      status: ConstitutionStatus.constitutional,
      timestamp: DateTime.now(),
      appliedConstraints: constraints,
    );

    debugPrint('🏛️ SELF-GOVERNANCE DECISION: [${type.name}] - $rationale');
    _decisionHistory.add(decision);

    // Notify the Client to execute this decision
    _executeDecision(decision);
  }

  void _executeDecision(AutonomousDecisionLog decision) {
    // Stage G14: Broadcaster for autonomous enforcement
    _lastDecision.value = decision;
  }

  /// Emergency Manual Halt of Autonomy (Requires Constitutional Permission).
  void toggleAutonomy(bool active) {
    debugPrint('⚠️ GOVERNANCE: Autonomy mode set to $active.');
    _isAutonomousMode.value = active;
  }

  void clearLogs() {
    _decisionHistory.clear();
  }

  @override
  void onClose() {
    clearLogs();
    super.onClose();
  }
}
