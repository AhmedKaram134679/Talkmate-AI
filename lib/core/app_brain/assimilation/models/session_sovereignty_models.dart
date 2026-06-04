/// Role-based authority within a live session.
enum SessionRole {
  host,
  moderator,
  participant,
  viewer,
  systemAuthority, // The AI Governor
}

/// Sovereign actions that can be taken within a session.
enum SovereignAction {
  mute,
  unmute,
  restrictVideo,
  allowVideo,
  kick,
  terminateSession,
  softAlert, // Internal warning
}

/// Metadata signals for Live Intelligence (Non-Intrusive).
enum IntelligenceSignalType {
  audioLevel, // Decibel level (No content)
  bitrateStability,
  packetLoss,
  frameRate,
  userChurn, // Join/Leave frequency
  consecutiveReconnects,
}

/// Protocol for decision escalation within a session.
enum EscalationLevel {
  none,
  alert, // Log/Notify internal systems
  intervention, // Partial restriction (Mute/Low Quality)
  hardKill, // Immediate Termination
}

/// Model for Session Health Report (No content storage).
class SessionHealthReport {
  final String sessionId;
  final Duration duration;
  final int participantCount;
  final List<SovereignIntervention> interventions;
  final double stabilityScore; // 0.0 to 1.0
  final DateTime timestamp;

  SessionHealthReport({
    required this.sessionId,
    required this.duration,
    required this.participantCount,
    required this.interventions,
    required this.stabilityScore,
    required this.timestamp,
  });
}

class SovereignIntervention {
  final SovereignAction action;
  final String reason;
  final DateTime timestamp;

  SovereignIntervention({
    required this.action,
    required this.reason,
    required this.timestamp,
  });
}
