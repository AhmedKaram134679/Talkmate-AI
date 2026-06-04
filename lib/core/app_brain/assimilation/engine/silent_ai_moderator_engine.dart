import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/ai_sovereignty_models.dart';
import '../models/session_sovereignty_models.dart';

/// Silent AI Co-Moderator Engine (F5 - Limited Sovereign Delegation).
/// Analyzes technical metadata to provide advisor-only recommendations.
class SilentAICoModeratorEngine extends GetxService {
  final Map<String, List<AiSovereignRecommendation>> _recommendationHistory =
      {};

  /// Analyzes session metadata signals and issues a non-binding recommendation.
  AiSovereignRecommendation? analyzeAndRecommend(
      String sessionId, IntelligenceSignalType type, double value) {
    debugPrint('🤖 SilentAI: Observing signal ($type) for $sessionId...');

    // Privacy Guard: Pure metadata analysis, no content touch.
    AiSovereignRecommendation? recommendation;

    if (type == IntelligenceSignalType.packetLoss && value > 0.3) {
      recommendation = _createRecommendation(
          sessionId,
          SovereignAction.restrictVideo,
          RecommendationRisk.high,
          'Technical diagnosis: Sustained high packet loss ($value) threatening session stability.');
    } else if (type == IntelligenceSignalType.audioLevel && value > 95) {
      recommendation = _createRecommendation(
          sessionId,
          SovereignAction.mute,
          RecommendationRisk.medium,
          'Socio-technical diagnosis: Extreme audio amplitude detected. Recommended mute to protect participant ears.');
    }

    if (recommendation != null) {
      _recommendationHistory
          .putIfAbsent(sessionId, () => [])
          .add(recommendation);
      debugPrint(
          '💡 SILENT AI SUGGESTION: ${recommendation.actionSuggested} | Reason: ${recommendation.technicalJustification}');
    }

    return recommendation;
  }

  AiSovereignRecommendation _createRecommendation(String sessionId,
      SovereignAction action, RecommendationRisk risk, String justification) {
    final now = DateTime.now();
    return AiSovereignRecommendation(
      recommendationId: 'ai_rec_${now.millisecondsSinceEpoch}',
      sessionId: sessionId,
      actionSuggested: action,
      risk: risk,
      technicalJustification: justification,
      createdAt: now,
      expiresAt: now.add(const Duration(seconds: 30)), // Strict TTL
    );
  }

  void purgeSessionAiData(String sessionId) {
    debugPrint('🧼 SilentAI: Purging AI advisory data for $sessionId.');
    _recommendationHistory.remove(sessionId);
  }
}
