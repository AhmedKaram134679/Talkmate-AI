/// AI Moderation states for sovereign rooms (G9).
enum AIModerationState {
  idle,
  analyzing,
  alerting,
  filtering,
  terminated,
}

/// Types of content violations detectable by AI.
enum ContentViolationType {
  none,
  excessiveNoise,
  toxicLanguage,
  inappropriateVisual,
  policyBreach,
  securityRisk,
}

/// Severity levels for AI alerts.
enum AIAlertSeverity {
  low, // Subtle suggestion
  medium, // Clear warning/notification
  high, // Immediate intervention required
  critical, // Automatic kill triggered
}

/// Model representing an AI moderation event.
class AIModerationEvent {
  final String id;
  final String userId;
  final ContentViolationType type;
  final AIAlertSeverity severity;
  final String message;
  final DateTime timestamp;
  final bool requiresConsent;

  AIModerationEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.severity,
    required this.message,
    required this.timestamp,
    this.requiresConsent = true,
  });
}

/// AI Assistance suggestions (Summaries, Actions).
class AIAssistanceSuggestion {
  final String id;
  final String title;
  final String content;
  final List<String> actions;
  final DateTime timestamp;

  AIAssistanceSuggestion({
    required this.id,
    required this.title,
    required this.content,
    required this.actions,
    required this.timestamp,
  });
}
