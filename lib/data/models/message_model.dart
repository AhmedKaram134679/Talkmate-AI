enum MessageType {
  text,
  image,
  audio,
  video,
  file,
  system,
  chat,
  call,
  location,
  contact
}

enum MessageStatus { pending, sent, delivered, read, failed }

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final MessageType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? mediaSize;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? editedAt;
  final Map<String, String>? reactions;
  final Map<String, bool>? deletedFor;
  final Map<String, int>? reactionCounts;
  final bool? deleted;
  final String?
      localId; // Client-generated ID for idempotency and offline tracking
  final String? replyToMessageId;
  final String? deletedByName;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.type = MessageType.text,
    this.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaSize,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.editedAt,
    this.reactions,
    this.deletedFor,
    this.reactionCounts,
    this.deleted,
    this.localId,
    this.replyToMessageId,
    this.deletedByName,
  });

  factory Message.fromJson(Map<String, dynamic> json, String docId) {
    // Helper to safely parse enums
    T parseEnum<T extends Enum>(List<T> values, String? value, T defaultValue) {
      if (value == null) return defaultValue;
      try {
        return values.byName(value);
      } catch (_) {
        return defaultValue;
      }
    }

    // Safe parsing for reactions and counts
    Map<String, String>? parsedReactions;
    Map<String, int>? parsedCounts;

    final reactionsRaw = json['reactions'];
    if (reactionsRaw is Map) {
      if (reactionsRaw.containsKey('user_reactions')) {
        // V3 Structured Format
        final ur = reactionsRaw['user_reactions'];
        if (ur is Map) {
          parsedReactions =
              ur.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        final c = reactionsRaw['counts'];
        if (c is Map) {
          parsedCounts = c.map((k, v) =>
              MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0));
        }
      } else {
        // Legacy Format (userId -> emoji)
        parsedReactions =
            reactionsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));

        // Auto-calculate counts from the map since backend didn't provide them
        parsedCounts = {};
        for (final emoji in parsedReactions.values) {
          parsedCounts[emoji] = (parsedCounts[emoji] ?? 0) + 1;
        }
      }
    }

    return Message(
      id: docId,
      chatId: (json['chat_id'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      type: parseEnum(
          MessageType.values, json['type']?.toString(), MessageType.text),
      text: json['text']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      mediaSize: json['media_size'] != null
          ? int.tryParse(json['media_size'].toString())
          : null,
      status: parseEnum(
          MessageStatus.values, json['status']?.toString(), MessageStatus.sent),
      createdAt: DateTime.parse(
          json['created_at']?.toString() ?? DateTime.now().toIso8601String()),
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'].toString())
          : null,
      reactions: parsedReactions,
      reactionCounts: parsedCounts,
      deletedFor: json['deleted_for'] is Map
          ? Map<String, bool>.from(json['deleted_for'])
          : null,
      deleted: json['is_deleted'] == true,
      localId: json['local_id']?.toString(),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      deletedByName: json['deleted_by_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'sender_id': senderId,
      'type': type.name,
      'text': text,
      'media_url': mediaUrl,
      'thumbnail_url': thumbnailUrl,
      'media_size': mediaSize,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
      'reactions': reactions,
      'deleted_for': deletedFor,
      'is_deleted': deleted,
      'local_id': localId,
      'reply_to_message_id': replyToMessageId,
      'deleted_by_name': deletedByName,
    }..removeWhere((k, v) => v == null);
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    MessageType? type,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? mediaSize,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? editedAt,
    Map<String, String>? reactions,
    Map<String, bool>? deletedFor,
    Map<String, int>? reactionCounts,
    bool? deleted,
    String? localId,
    String? replyToMessageId,
    String? deletedByName,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaSize: mediaSize ?? this.mediaSize,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      deletedFor: deletedFor ?? this.deletedFor,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      deleted: deleted ?? this.deleted,
      localId: localId ?? this.localId,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      deletedByName: deletedByName ?? this.deletedByName,
    );
  }
}
