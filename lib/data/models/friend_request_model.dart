import 'package:flutter/foundation.dart';

enum FriendRequestStatus { pending, accepted, declined, canceled }

class FriendRequestModel {
  final String id;
  final String fromUserId;
  final String toUserId;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FriendRequestModel({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  FriendRequestModel copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    FriendRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      FriendRequestModel(
        id: id ?? this.id,
        fromUserId: fromUserId ?? this.fromUserId,
        toUserId: toUserId ?? this.toUserId,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static FriendRequestModel fromJson(Map<String, dynamic> json, String id) {
    try {
      final fromId =
          json['sender_id'] ?? json['from_user_id'] ?? json['fromUserId'];
      final toId =
          json['receiver_id'] ?? json['to_user_id'] ?? json['toUserId'];

      if (fromId == null || toId == null) {
        debugPrint(
            'Warning: Missing sender/receiver ID in FriendRequest JSON: $json');
      }

      return FriendRequestModel(
        id: id,
        fromUserId: fromId?.toString() ?? '',
        toUserId: toId?.toString() ?? '',
        status: _statusFromString(json['status']?.toString()),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint(
          'Error parsing FriendRequestModel: $e\nStack: $stack\nJSON: $json');
      // Return a dummy object or rethrow. Rethrowing lets the UI show the error but we want to know WHY.
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static FriendRequestStatus _statusFromString(String? s) {
    switch (s) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'declined':
        return FriendRequestStatus.declined;
      case 'canceled':
        return FriendRequestStatus.canceled;
      case 'pending':
      default:
        return FriendRequestStatus.pending;
    }
  }
}
