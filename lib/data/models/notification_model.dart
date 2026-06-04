// Removed cloud_firestore import

enum NotificationType { message, friendRequest, groupInvite, call }

class AppNotification {
  final String id;
  final String userId; // recipient
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.read = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json, String docId) {
    return AppNotification(
      id: docId,
      userId: json['userId'] as String? ?? '',
      type: _typeFromString(json['type'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: (json['data'] as Map?)?.cast<String, dynamic>(),
      read: json['read'] as bool? ?? false,
      createdAt: _tsToDate(json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'type': type.name,
      'title': title,
      'body': body,
      'data': data,
      'read': read,
      'created_at': createdAt.toIso8601String(),
    }..removeWhere((k, v) => v == null);
  }

  AppNotification markRead([bool value = true]) => AppNotification(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        data: data,
        read: value,
        createdAt: createdAt,
      );

  static DateTime? _tsToDate(dynamic v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static NotificationType _typeFromString(String? s) {
    switch (s) {
      case 'friendRequest':
        return NotificationType.friendRequest;
      case 'groupInvite':
        return NotificationType.groupInvite;
      case 'call':
        return NotificationType.call;
      case 'message':
      default:
        return NotificationType.message;
    }
  }
}
