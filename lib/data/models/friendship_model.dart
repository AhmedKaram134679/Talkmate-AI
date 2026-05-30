// Removed cloud_firestore import

class FriendshipModel {
  final String id;
  final String userA;
  final String userB;
  final DateTime createdAt;

  const FriendshipModel({
    required this.id,
    required this.userA,
    required this.userB,
    required this.createdAt,
  });

  FriendshipModel copyWith({
    String? id,
    String? userA,
    String? userB,
    DateTime? createdAt,
  }) =>
      FriendshipModel(
        id: id ?? this.id,
        userA: userA ?? this.userA,
        userB: userB ?? this.userB,
        createdAt: createdAt ?? this.createdAt,
      );

  static FriendshipModel fromJson(Map<String, dynamic> json, String id) {
    return FriendshipModel(
      id: id,
      userA: (json['user_a'] ?? json['userA']) as String,
      userB: (json['user_b'] ?? json['userB']) as String,
      createdAt:
          DateTime.parse(json['created_at'] ?? json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_a': userA,
      'user_b': userB,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
