/// Quality levels for call participants.
enum CallQuality {
  audioOnly,
  lowVideo,
  highVideo,
}

/// Profile for an individual participant in a call.
class ParticipantCallProfile {
  final String participantId;
  CallQuality quality;
  bool isMuted;
  double? bandwidthLimitKbps;

  ParticipantCallProfile({
    required this.participantId,
    this.quality = CallQuality.audioOnly,
    this.isMuted = false,
    this.bandwidthLimitKbps,
  });

  @override
  String toString() =>
      'Participant($participantId, ${quality.name}, Muted: $isMuted)';
}
