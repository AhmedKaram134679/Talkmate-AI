import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:uuid/uuid.dart';

import 'message_model.dart';

enum ChatType { individual, group, channel }

class ChatModel {
  final String id;
  final String name;
  final String? description;
  final String? avatar;
  final ChatType type;
  final List<String> participantIds;
  final String? lastMessageId;
  final MessageModel? lastMessage;
  final DateTime? lastActivity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final bool isArchived;
  final bool isMuted;
  final DateTime? muteUntil;
  final bool isPinned;
  final int unreadCount;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? metadata;

  ChatModel({
    String? id,
    required this.name,
    this.description,
    this.avatar,
    this.type = ChatType.individual,
    required this.participantIds,
    this.lastMessageId,
    this.lastMessage,
    this.lastActivity,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.createdBy,
    this.isArchived = false,
    this.isMuted = false,
    this.muteUntil,
    this.isPinned = false,
    this.unreadCount = 0,
    this.settings,
    this.metadata,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Factory constructor for creating from JSON
  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      avatar: json['avatar'] as String?,
      type: ChatType.values.firstWhere(
        (e) => e.toString() == 'ChatType.${json['type']}',
        orElse: () => ChatType.individual,
      ),
      participantIds: (json['participantIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      lastMessageId: json['lastMessageId'] as String?,
      lastMessage: json['lastMessage'] != null
          ? MessageModel.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      lastActivity: json['lastActivity'] != null
          ? DateTime.parse(json['lastActivity'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      createdBy: json['createdBy'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      muteUntil: json['muteUntil'] != null
          ? DateTime.parse(json['muteUntil'] as String)
          : null,
      isPinned: json['isPinned'] as bool? ?? false,
      unreadCount: json['unreadCount'] as int? ?? 0,
      settings: json['settings'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar': avatar,
      'type': type.toString().split('.').last,
      'participantIds': participantIds,
      'lastMessageId': lastMessageId,
      'lastMessage': lastMessage?.toJson(),
      'lastActivity': lastActivity?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'createdBy': createdBy,
      'isArchived': isArchived,
      'isMuted': isMuted,
      'muteUntil': muteUntil?.toIso8601String(),
      'isPinned': isPinned,
      'unreadCount': unreadCount,
      'settings': settings,
      'metadata': metadata,
    };
  }

  // Copy with method for updating chat data
  ChatModel copyWith({
    String? name,
    String? description,
    String? avatar,
    ChatType? type,
    List<String>? participantIds,
    String? lastMessageId,
    MessageModel? lastMessage,
    DateTime? lastActivity,
    DateTime? updatedAt,
    String? createdBy,
    bool? isArchived,
    bool? isMuted,
    DateTime? muteUntil,
    bool? isPinned,
    int? unreadCount,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? metadata,
  }) {
    return ChatModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatar: avatar ?? this.avatar,
      type: type ?? this.type,
      participantIds: participantIds ?? this.participantIds,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastActivity: lastActivity ?? this.lastActivity,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      createdBy: createdBy ?? this.createdBy,
      isArchived: isArchived ?? this.isArchived,
      isMuted: isMuted ?? this.isMuted,
      muteUntil: muteUntil ?? this.muteUntil,
      isPinned: isPinned ?? this.isPinned,
      unreadCount: unreadCount ?? this.unreadCount,
      settings: settings ?? this.settings,
      metadata: metadata ?? this.metadata,
    );
  }

  // Helper methods
  bool get isIndividual => type == ChatType.individual;
  bool get isGroup => type == ChatType.group;
  bool get isChannel => type == ChatType.channel;

  bool get hasUnreadMessages => unreadCount > 0;
  bool get hasLastMessage => lastMessage != null;

  String getTypeText(AppLocalizations l10n) {
    switch (type) {
      case ChatType.individual:
        return l10n.chatTypeIndividual;
      case ChatType.group:
        return l10n.chatTypeGroup;
      case ChatType.channel:
        return l10n.chatTypeChannel;
    }
  }

  String getDisplayName(AppLocalizations l10n) {
    if (name.isNotEmpty) return name;
    if (isIndividual && participantIds.length == 2) {
      return l10n.chatTypeIndividual;
    }
    return l10n.chatTypeChat;
  }

  String getLastMessageText(AppLocalizations l10n) {
    if (lastMessage == null) return l10n.noMessages;
    return lastMessage!.getDisplayContent(l10n);
  }

  String getLastActivityText(AppLocalizations l10n) {
    if (lastActivity == null) return '';
    final now = DateTime.now();
    final difference = now.difference(lastActivity!);

    if (difference.inMinutes < 1) {
      return l10n.timeNow;
    } else if (difference.inHours < 1) {
      return l10n.timeMinutes(difference.inMinutes);
    } else if (difference.inDays < 1) {
      return l10n.timeHours(difference.inHours);
    } else if (difference.inDays < 7) {
      return l10n.timeDays(difference.inDays);
    } else {
      return l10n.timeWeeks((difference.inDays / 7).floor());
    }
  }

  int get participantCount => participantIds.length;

  bool isParticipant(String userId) => participantIds.contains(userId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatModel(id: $id, name: $name, type: $type, participants: ${participantIds.length})';
  }

  // Static method for creating an individual chat
  static ChatModel individual({
    required String participant1Id,
    required String participant2Id,
    String? name,
  }) {
    return ChatModel(
      name: name ?? 'محادثة فردية',
      type: ChatType.individual,
      participantIds: [participant1Id, participant2Id],
    );
  }

  // Static method for creating a group chat
  static ChatModel group({
    required String name,
    required List<String> participantIds,
    required String createdBy,
    String? description,
    String? avatar,
  }) {
    return ChatModel(
      name: name,
      description: description,
      avatar: avatar,
      type: ChatType.group,
      participantIds: participantIds,
      createdBy: createdBy,
    );
  }

  // Static method for creating a mock chat for testing
  static ChatModel mock({
    String? name,
    ChatType? type,
    List<String>? participantIds,
    int? unreadCount,
  }) {
    return ChatModel(
      name: name ?? 'محادثة تجريبية',
      type: type ?? ChatType.individual,
      participantIds: participantIds ??
          [
            'user1_${DateTime.now().millisecondsSinceEpoch}',
            'user2_${DateTime.now().millisecondsSinceEpoch}',
          ],
      unreadCount: unreadCount ?? 0,
      lastActivity: DateTime.now().subtract(const Duration(minutes: 5)),
      lastMessage: MessageModel.mock(),
    );
  }
}
