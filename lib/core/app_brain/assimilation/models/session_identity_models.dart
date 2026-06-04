import 'session_sovereignty_models.dart';

/// Verification level of a participant's identity.
enum VerificationLevel {
  anonymous,
  softVerified, // Verified by invite/link
  fullyVerified, // Authenticated via system
}

/// The context through which a participant joined the session.
enum JoinContext {
  invite,
  link,
  approvedEntry,
  directDial,
}

/// Sovereign Identity of a participant in a specific session.
class SessionParticipant {
  final String participantId;
  final String userId; // System UID (Protected)
  final SessionRole role;
  final VerificationLevel verification;
  final JoinContext context;
  final DateTime joinedAt;

  SessionParticipant({
    required this.participantId,
    required this.userId,
    required this.role,
    required this.verification,
    required this.context,
    required this.joinedAt,
  });
}

/// Status of a participant's trust and eligibility.
class ParticipantTrustStatus {
  final String participantId;
  double trustScore; // 0.0 to 100.0
  final bool isContextualOnly; // Always true in F4

  ParticipantTrustStatus({
    required this.participantId,
    this.trustScore = 50.0, // Default baseline
    this.isContextualOnly = true,
  });
}

/// Dynamic permissions for a participant.
class SessionPermissions {
  final bool canSpeak;
  final bool canUseVideo;
  final bool canInvite;
  final bool canShareScreen;
  final bool canModerate; // Soft control

  SessionPermissions({
    this.canSpeak = true,
    this.canUseVideo = false,
    this.canInvite = false,
    this.canShareScreen = false,
    this.canModerate = false,
  });

  factory SessionPermissions.fromRole(SessionRole role) {
    switch (role) {
      case SessionRole.host:
      case SessionRole.systemAuthority:
        return SessionPermissions(
            canSpeak: true,
            canUseVideo: true,
            canInvite: true,
            canShareScreen: true,
            canModerate: true);
      case SessionRole.moderator:
        return SessionPermissions(
            canSpeak: true,
            canUseVideo: true,
            canInvite: true,
            canShareScreen: true,
            canModerate: true);
      case SessionRole.participant:
        return SessionPermissions(canSpeak: true, canUseVideo: true);
      case SessionRole.viewer:
        return SessionPermissions(canSpeak: false, canUseVideo: false);
    }
  }
}
