/// Recording states for sovereign rooms (G8).
enum RecordingState {
  initializing,
  recording,
  paused,
  stopping,
  stopped,
  failed,
}

/// Types of tracks that can be recorded.
enum RecordingTrackType {
  audio,
  video,
  screenShare,
  combined,
}

/// Privacy and access levels for recordings.
enum RecordingPrivacy {
  private, // Only owner can access
  group, // Participants of the room can access
  public, // Public link (not recommended for sovereign use)
  institutional // Controlled by institution policy
}

/// Model representing a recording session info.
class RecordingSession {
  final String id;
  final String roomId;
  final String ownerId;
  final RecordingState state;
  final Set<RecordingTrackType> tracks;
  final DateTime startedAt;
  final DateTime? endedAt;
  final RecordingPrivacy privacy;

  RecordingSession({
    required this.id,
    required this.roomId,
    required this.ownerId,
    required this.state,
    required this.tracks,
    required this.startedAt,
    this.endedAt,
    this.privacy = RecordingPrivacy.private,
  });

  RecordingSession copyWith({
    RecordingState? state,
    DateTime? endedAt,
    RecordingPrivacy? privacy,
  }) {
    return RecordingSession(
      id: id,
      roomId: roomId,
      ownerId: ownerId,
      state: state ?? this.state,
      tracks: tracks,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      privacy: privacy ?? this.privacy,
    );
  }
}
