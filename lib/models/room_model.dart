import 'package:uuid/uuid.dart';

enum RoomType { voice, video }

enum RoomStatus { active, empty, hidden }

class RoomModel {
  final String id;
  final String name;
  final RoomType type;
  final RoomStatus status;
  final int participantCount;
  final DateTime createdAt;
  final String? createdBy;
  final String? activeSessionId;
  final String? topic;
  final Map<String, dynamic> metadata;

  RoomModel({
    String? id,
    required this.name,
    required this.type,
    this.status = RoomStatus.empty,
    this.participantCount = 0,
    DateTime? createdAt,
    this.createdBy,
    this.activeSessionId,
    this.topic,
    this.metadata = const {},
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  RoomModel copyWith({
    String? name,
    RoomType? type,
    RoomStatus? status,
    int? participantCount,
    String? createdBy,
    String? activeSessionId,
    String? topic,
    Map<String, dynamic>? metadata,
  }) {
    return RoomModel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      participantCount: participantCount ?? this.participantCount,
      createdAt: createdAt,
      createdBy: createdBy ?? this.createdBy,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      topic: topic ?? this.topic,
      metadata: metadata ?? this.metadata,
    );
  }

  // Support for temporary session-based rooms
  bool get isTemporary => true;

  @override
  String toString() =>
      'RoomModel(id: $id, name: $name, type: ${type.name}, status: ${status.name}, participants: $participantCount)';
}
