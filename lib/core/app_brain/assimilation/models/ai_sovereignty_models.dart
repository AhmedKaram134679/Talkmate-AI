import 'session_sovereignty_models.dart';

/// Levels of technical risk/urgency for AI recommendations.
enum RecommendationRisk {
  low, // Optimization suggestion
  medium, // Performance warning
  high, // Stability threat
  critical, // System integrity threat
}

/// A non-binding sovereign recommendation issued by the Silent AI.
class AiSovereignRecommendation {
  final String recommendationId;
  final String sessionId;
  final SovereignAction actionSuggested;
  final RecommendationRisk risk;
  final String technicalJustification; // Based on Metadata only
  final DateTime createdAt;
  final DateTime expiresAt;
  bool isHandled; // Whether it was accepted, rejected, or ignored

  AiSovereignRecommendation({
    required this.recommendationId,
    required this.sessionId,
    required this.actionSuggested,
    required this.risk,
    required this.technicalJustification,
    required this.createdAt,
    required this.expiresAt,
    this.isHandled = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Metadata-based diagnostic for the recommendation.
class AiDiagnosticSignal {
  final IntelligenceSignalType type;
  final double value;
  final String observation;

  AiDiagnosticSignal({
    required this.type,
    required this.value,
    required this.observation,
  });
}
