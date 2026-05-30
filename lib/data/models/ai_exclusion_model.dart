class AiExclusion {
  final String id;
  final String userId;
  final String chatId;
  final DateTime createdAt;

  AiExclusion({
    required this.id,
    required this.userId,
    required this.chatId,
    required this.createdAt,
  });

  factory AiExclusion.fromJson(Map<String, dynamic> json) {
    return AiExclusion(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      chatId: json['chat_id'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'chat_id': chatId,
    };
  }
}
