import 'dart:convert';

enum SyncActionType {
  markRead,
  markDelivered,
  updateMetadata, // for pin/mute/archive
}

class SyncAction {
  final String id;
  final SyncActionType type;
  final String? chatId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  SyncAction({
    required this.id,
    required this.type,
    this.chatId,
    required this.payload,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action_type': type.name,
      'chat_id': chatId,
      'payload': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SyncAction.fromMap(Map<String, dynamic> map) {
    return SyncAction(
      id: map['id'] as String,
      type: SyncActionType.values.firstWhere(
        (e) => e.name == map['action_type'],
        orElse: () => SyncActionType.markRead,
      ),
      chatId: map['chat_id'] as String?,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
