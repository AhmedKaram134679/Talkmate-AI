import 'participant_call_profile.dart';

/// Represents a multi-party call session.
class CallSession {
  final String sessionId;
  final List<ParticipantCallProfile> participants;
  final bool isGroupCall;

  CallSession({
    required this.sessionId,
    required this.participants,
  }) : isGroupCall = participants.length > 2;

  void addParticipant(ParticipantCallProfile profile) {
    participants.add(profile);
  }

  void removeParticipant(String participantId) {
    participants.removeWhere((p) => p.participantId == participantId);
  }

  ParticipantCallProfile? getParticipant(String id) =>
      participants.firstWhere((p) => p.participantId == id);

  @override
  String toString() => 'CallSession($sessionId, Count: ${participants.length})';
}
