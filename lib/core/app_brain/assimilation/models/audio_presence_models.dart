/// Sovereign Audio Presence States (G6).
enum AudioPresenceState {
  silent,
  requestingToSpeak,
  speaking,
  mutedSelf,
  mutedSystem,
  listeningOnly,
}

/// Mute types defined by the sovereignty constitution.
enum MuteType {
  self, // Absolute user right
  system, // Protective/Technical
  hostReq, // Administrative request (not forced)
}

/// Token representing audio priority for a participant.
class AudioPriorityToken {
  final int level; // 0 (lowest) to 10 (emergency)
  final DateTime issuedAt;
  final String? reason;

  const AudioPriorityToken({
    this.level = 1,
    required this.issuedAt,
    this.reason,
  });

  bool get isHighPriority => level > 7;
}

/// Metadata for an audio state change.
class AudioStateChange {
  final AudioPresenceState oldState;
  final AudioPresenceState newState;
  final String? actorId; // Who triggered the change
  final String? reason;
  final DateTime timestamp;

  AudioStateChange({
    required this.oldState,
    required this.newState,
    this.actorId,
    this.reason,
    required this.timestamp,
  });
}
