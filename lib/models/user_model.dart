import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:uuid/uuid.dart';

enum UserStatus {
  online,
  offline,
  away,
  busy,
  inCall,
  inRoomVoice,
  inRoomVideo
}

class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? profilePicture;
  final String? bio;
  final UserStatus status;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isVerified;
  final bool isBlocked;
  final Map<String, dynamic>? settings;

  UserModel({
    String? id,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.profilePicture,
    this.bio,
    this.status = UserStatus.offline,
    this.lastSeen,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isVerified = false,
    this.isBlocked = false,
    this.settings,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Factory constructor for creating from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      profilePicture: json['profilePicture'] as String?,
      bio: json['bio'] as String?,
      status: UserStatus.values.firstWhere(
        (e) => e.toString() == 'UserStatus.${json['status']}',
        orElse: () => UserStatus.offline,
      ),
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isVerified: json['isVerified'] as bool? ?? false,
      isBlocked: json['isBlocked'] as bool? ?? false,
      settings: json['settings'] as Map<String, dynamic>?,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'profilePicture': profilePicture,
      'bio': bio,
      'status': status.toString().split('.').last,
      'lastSeen': lastSeen?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isVerified': isVerified,
      'isBlocked': isBlocked,
      'settings': settings,
    };
  }

  // Copy with method for updating user data
  UserModel copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? profilePicture,
    String? bio,
    UserStatus? status,
    DateTime? lastSeen,
    DateTime? updatedAt,
    bool? isVerified,
    bool? isBlocked,
    Map<String, dynamic>? settings,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicture: profilePicture ?? this.profilePicture,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isVerified: isVerified ?? this.isVerified,
      isBlocked: isBlocked ?? this.isBlocked,
      settings: settings ?? this.settings,
    );
  }

  // Helper methods
  bool get isOnline => status == UserStatus.online;
  bool get isOffline => status == UserStatus.offline;
  bool get isAway => status == UserStatus.away;
  bool get isBusy => status == UserStatus.busy;

  String getStatusText(AppLocalizations l10n) {
    switch (status) {
      case UserStatus.online:
        return l10n.statusOnline;
      case UserStatus.offline:
        return l10n.statusOffline;
      case UserStatus.away:
        return l10n.statusAway;
      case UserStatus.busy:
        return l10n.statusBusy;
      case UserStatus.inCall:
        // [Hotfix]: Use hardcoded fallback until l10n generation syncs
        return 'In a call';
      case UserStatus.inRoomVoice:
        return 'In voice room';
      case UserStatus.inRoomVideo:
        return 'In video room';
    }
  }

  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  String get initials {
    if (name.isEmpty) return '?';
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email, status: $status)';
  }

  // Static method for creating a guest user
  static UserModel guest() {
    return UserModel(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Guest', // Localized at UI level if needed
      email: 'guest@talkmate.ai',
      status: UserStatus.online,
    );
  }

  // Static method for creating a mock user for testing
  static UserModel mock({
    String? name,
    String? email,
    UserStatus? status,
  }) {
    return UserModel(
      name: name ?? 'مستخدم تجريبي',
      email: email ?? 'test@talkmate.ai',
      status: status ?? UserStatus.online,
      isVerified: true,
      bio: 'هذا مستخدم تجريبي لاختبار التطبيق',
    );
  }
}
