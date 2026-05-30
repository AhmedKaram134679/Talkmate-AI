class Chat {
  final String id;
  final List<String> participantIds;
  final bool isGroup;
  final String? groupName;
  final String? groupPhotoUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? lastMessageText;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final bool? isPinned;
  final bool? isMuted;
  final DateTime? muteUntil;
  final bool? isArchived;
  final String? groupDescription;
  final String? creatorId;

  const Chat({
    required this.id,
    required this.participantIds,
    this.isGroup = false,
    this.groupName,
    this.groupPhotoUrl,
    required this.createdAt,
    this.updatedAt,
    this.lastMessageText,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.isPinned,
    this.isMuted,
    this.muteUntil,
    this.isArchived,
    this.groupDescription,
    this.creatorId,
  });

  factory Chat.fromJson(Map<String, dynamic> json, String docId) {
    return Chat(
      id: docId,
      participantIds: (json['participant_ids'] as List?)?.cast<String>() ??
          (json['participantIds'] as List?)?.cast<String>() ??
          const [],
      isGroup: json['is_group'] ?? json['isGroup'] ?? false,
      groupName: json['group_name'] ?? json['groupName'],
      groupPhotoUrl: json['group_photo_url'] ?? json['groupPhotoUrl'],
      createdAt: DateTime.parse(json['created_at'] ??
          json['createdAt'] ??
          DateTime.now().toIso8601String()),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : json['updatedAt'] != null
              ? DateTime.parse(json['updatedAt'])
              : null,
      lastMessageText: json['last_message_text'] ?? json['lastMessageText'],
      lastMessageSenderId:
          json['last_message_sender_id'] ?? json['lastMessageSenderId'],
      lastMessageAt: (json['last_message_time'] != null)
          ? DateTime.parse(json['last_message_time'])
          : (json['lastMessageAt'] != null)
              ? DateTime.parse(json['lastMessageAt'])
              : null,
      isPinned: json['is_pinned'] ?? json['isPinned'],
      isMuted: json['is_muted'] ?? json['isMuted'],
      muteUntil: (json['mute_until'] != null)
          ? DateTime.parse(json['mute_until'])
          : null,
      isArchived: json['is_archived'] ?? json['isArchived'],
      groupDescription: json['group_description'] ?? json['groupDescription'],
      creatorId: json['creator_id'] ?? json['creatorId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participant_ids': participantIds,
      'is_group': isGroup,
      'group_name': groupName,
      'group_photo_url': groupPhotoUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'last_message_text': lastMessageText,
      'last_message_sender_id': lastMessageSenderId,
      'last_message_time': lastMessageAt?.toIso8601String(),
      'is_pinned': isPinned,
      'is_muted': isMuted,
      'mute_until': muteUntil?.toIso8601String(),
      'is_archived': isArchived,
      'group_description': groupDescription,
      'creator_id': creatorId,
    }..removeWhere((k, v) => v == null);
  }
}
