/// نموذج مؤشر الكتابة للمحادثات الفورية
class TypingIndicator {
  final String chatId;
  final String userId;
  final DateTime startedAt;
  final DateTime? lastUpdatedAt;

  const TypingIndicator({
    required this.chatId,
    required this.userId,
    required this.startedAt,
    this.lastUpdatedAt,
  });

  TypingIndicator copyWith({
    String? chatId,
    String? userId,
    DateTime? startedAt,
    DateTime? lastUpdatedAt,
  }) =>
      TypingIndicator(
        chatId: chatId ?? this.chatId,
        userId: userId ?? this.userId,
        startedAt: startedAt ?? this.startedAt,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      );

  static TypingIndicator fromJson(Map<String, dynamic> json) {
    return TypingIndicator(
      chatId: (json['chat_id'] ?? json['chatId']) as String,
      userId: (json['user_id'] ?? json['userId']) as String,
      startedAt:
          DateTime.parse(json['started_at'] ?? json['startedAt'] as String),
      lastUpdatedAt: (json['last_updated_at'] ?? json['lastUpdatedAt']) != null
          ? DateTime.parse(
              (json['last_updated_at'] ?? json['lastUpdatedAt']) as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'started_at': startedAt.toIso8601String(),
      'last_updated_at': lastUpdatedAt?.toIso8601String(),
    }..removeWhere((k, v) => v == null);
  }

  /// يتحقق من انتهاء صلاحية مؤشر الكتابة (أكثر من 5 ثوان)
  bool get isExpired {
    final now = DateTime.now();
    final lastActivity = lastUpdatedAt ?? startedAt;
    return now.difference(lastActivity).inSeconds > 5;
  }
}
