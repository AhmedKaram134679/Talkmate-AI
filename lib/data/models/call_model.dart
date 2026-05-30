enum CallType { audio, video }

enum CallStatus { ringing, accepted, ongoing, ended, missed, rejected, failed }

class CallSession {
  final String id;
  final String senderId;
  final String receiverId;
  final CallType type;
  final CallStatus status;
  final String? roomId; // for WebRTC
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final List<dynamic>? candidates;
  final Map<String, dynamic>? metadata; // Added for Supabase/FCM metadata

  const CallSession({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    this.status = CallStatus.ringing,
    this.roomId,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.offer,
    this.answer,
    this.candidates,
    this.metadata,
  });

  bool get isVideo => type == CallType.video;
  bool get isAudio => type == CallType.audio;

  factory CallSession.fromJson(Map<String, dynamic> json, String docId) {
    return CallSession(
      id: docId,
      senderId: (json['caller_id'] ?? json['sender_id'] ?? json['callerId'])
              as String? ??
          '',
      receiverId: (json['receiver_id'] ?? json['callee_id'] ?? json['calleeId'])
              as String? ??
          '',
      type: _typeFromString(json['type'] as String?),
      status: _statusFromString(json['status'] as String?),
      roomId: (json['room_id'] ?? json['roomId']) as String?,
      createdAt:
          _tsToDate(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
      startedAt: _tsToDate(json['started_at'] ?? json['startedAt']),
      endedAt: _tsToDate(json['ended_at'] ?? json['endedAt']),
      offer: json['offer'] as Map<String, dynamic>?,
      answer: json['answer'] as Map<String, dynamic>?,
      candidates: json['candidates'] as List<dynamic>?,
      metadata: json, // Hold all data in metadata for signaling
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caller_id': senderId,
      'receiver_id': receiverId,
      'type': type.name,
      'status': status.name,
      'room_id': roomId,
      'created_at': createdAt.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'offer': offer,
      'answer': answer,
      'candidates': candidates,
    }..removeWhere((k, v) => v == null);
  }

  CallSession copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    CallType? type,
    CallStatus? status,
    String? roomId,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
    List<dynamic>? candidates,
    Map<String, dynamic>? metadata,
  }) {
    return CallSession(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      status: status ?? this.status,
      roomId: roomId ?? this.roomId,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      candidates: candidates ?? this.candidates,
      metadata: metadata ?? this.metadata,
    );
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static CallType _typeFromString(String? s) {
    switch (s) {
      case 'video':
        return CallType.video;
      case 'audio':
      default:
        return CallType.audio;
    }
  }

  static CallStatus _statusFromString(String? s) {
    switch (s) {
      case 'accepted':
        return CallStatus.accepted;
      case 'ongoing':
        return CallStatus.ongoing;
      case 'ended':
        return CallStatus.ended;
      case 'missed':
        return CallStatus.missed;
      case 'rejected':
        return CallStatus.rejected;
      case 'failed':
        return CallStatus.failed;
      case 'ringing':
      default:
        return CallStatus.ringing;
    }
  }
}
