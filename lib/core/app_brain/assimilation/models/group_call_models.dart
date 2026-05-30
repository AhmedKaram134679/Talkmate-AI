/// Participant states in a group call (G5).
enum ParticipantMediaState {
  joining,
  verifying,
  active,
  muted,
  suspended,
  leaving,
}

/// Participant roles within a group call.
enum ParticipantRole {
  host,
  moderator,
  guest,
  member,
}

/// Model representing a participant in a group session.
class GroupParticipant {
  final String userId;
  final String displayName;
  final ParticipantRole role;
  final ParticipantMediaState state;
  final DateTime joinedAt;
  final bool isMuted;

  GroupParticipant({
    required this.userId,
    required this.displayName,
    required this.role,
    this.state = ParticipantMediaState.joining,
    required this.joinedAt,
    this.isMuted = false,
  });

  GroupParticipant copyWith({
    ParticipantMediaState? state,
    bool? isMuted,
  }) {
    return GroupParticipant(
      userId: userId,
      displayName: displayName,
      role: role,
      state: state ?? this.state,
      joinedAt: joinedAt,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

/// Configuration for group call sessions.
class GroupCallConfig {
  final int maxParticipants;
  final bool allowGuestMute;
  final Duration joinTimeout;

  const GroupCallConfig({
    this.maxParticipants = 50,
    this.allowGuestMute = true,
    this.joinTimeout = const Duration(seconds: 30),
  });
}
