import 'package:talkmate_ai/data/models/call_model.dart';

abstract class ICallRepository {
  Future<CallSession> createCall({
    required String senderId,
    required String receiverId,
    bool isVideo = false,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  });

  Stream<CallSession?> watchById(String callId);
  Future<CallSession?> getById(String callId);

  Future<void> updateStatus(String callId, CallStatus status);
  Future<void> updateMetadata(String callId, Map<String, dynamic> metadata);

  Stream<List<CallSession>> watchUserCalls(String userId, {int limit = 50});

  // WebRTC Signaling
  Future<void> setOffer(String callId, String sdp,
      {Map<String, dynamic>? extra});
  Future<void> setAnswer(String callId, String sdp,
      {Map<String, dynamic>? extra});
  Future<void> addCandidate(String callId, Map<String, dynamic> candidateData);
  Future<void> clearGhostCalls(String userId);
}
