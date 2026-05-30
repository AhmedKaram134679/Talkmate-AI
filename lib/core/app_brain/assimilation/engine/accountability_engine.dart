import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/accountability_models.dart';
import '../models/session_sovereignty_models.dart';

/// Institutional Accountability Engine (F6).
/// Responsible for documenting, explaining, and auditing sovereign actions.
class InstitutionalAccountabilityEngine extends GetxService {
  final Map<String, List<AccountabilityRecord>> _auditLogs = {};

  /// Logs a sovereign decision with a technical explanation and integrity hash.
  void logSovereignDecision({
    required String sessionId,
    required SovereignAction action,
    required String authority,
    required String technicalBasis,
    required String policyReference,
  }) {
    final now = DateTime.now();
    final explanation = DecisionExplanation(
      policyId: policyReference,
      objective: 'Maintain Session Integrity',
      technicalBasis: technicalBasis,
      constitutionalArticle:
          'Governance Skeleton: Article ${action.name.toUpperCase()}',
    );

    final recordId =
        'audit_${now.millisecondsSinceEpoch}_${sessionId.hashCode}';
    final rawData =
        '$recordId|$sessionId|${action.name}|$authority|$technicalBasis';
    final hash = sha256.convert(utf8.encode(rawData)).toString();

    final record = AccountabilityRecord(
      recordId: recordId,
      sessionId: sessionId,
      action: action,
      authority: authority,
      explanation: explanation,
      timestamp: now,
      integrityHash: hash,
    );

    _auditLogs.putIfAbsent(sessionId, () => []).add(record);
    debugPrint(
        '🏛️ ACCOUNTABILITY: Sovereign decision logged for $sessionId. Reason: $technicalBasis');
  }

  /// Generates a non-media evidence pack for compliance review.
  SessionEvidencePack generateEvidencePack(
      String sessionId, ComplianceProfile profile) {
    debugPrint(
        '💼 ACCOUNTABILITY: Generating Evidence Pack for $sessionId [Profile: $profile]');

    return SessionEvidencePack(
      sessionId: sessionId,
      profile: profile,
      auditTrail: _auditLogs[sessionId] ?? [],
      qualityMetrics: {
        'avg_jitter': 0.15, // Mocked
        'stability_index': 0.98,
      },
      generatedAt: DateTime.now(),
    );
  }

  void purgeAccountabilityData(String sessionId) {
    debugPrint(
        '🧼 ACCOUNTABILITY: Purging audit logs for $sessionId (Privacy Compliance).');
    _auditLogs.remove(sessionId);
  }
}
