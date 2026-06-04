import 'package:uuid/uuid.dart';

enum InvitationType { individualCall, roomJoin }

enum InvitationStatus { pending, accepted, declined, expired }

class CommInvitation {
  final String id;
  final String senderId;
  final String senderName;
  final String targetId; // Receiver UserId
  final String? resourceId; // CallId or RoomId
  final InvitationType type;
  final InvitationStatus status;
  final DateTime createdAt;
  final bool isVideo;

  CommInvitation({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.targetId,
    this.resourceId,
    required this.type,
    this.status = InvitationStatus.pending,
    DateTime? createdAt,
    this.isVideo = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  CommInvitation copyWith({
    InvitationStatus? status,
    String? resourceId,
  }) {
    return CommInvitation(
      id: id,
      senderId: senderId,
      senderName: senderName,
      targetId: targetId,
      resourceId: resourceId ?? this.resourceId,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      isVideo: isVideo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'targetId': targetId,
      'resourceId': resourceId,
      'type': type.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'isVideo': isVideo,
    };
  }

  factory CommInvitation.fromJson(Map<String, dynamic> json) {
    return CommInvitation(
      id: json['id'],
      senderId: json['senderId'],
      senderName: json['senderName'],
      targetId: json['targetId'],
      resourceId: json['resourceId'],
      type: InvitationType.values.byName(json['type']),
      status: InvitationStatus.values.byName(json['status']),
      createdAt: DateTime.parse(json['createdAt']),
      isVideo: json['isVideo'] ?? false,
    );
  }
}
