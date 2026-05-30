enum UserStatus {
  online,
  offline,
  away,
  busy,
  inCall,
  inRoomVoice,
  inRoomVideo
}

class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? about;
  final List<String> fcmTokens;
  final UserStatus status;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final bool privacyShowLastSeen;
  final bool privacyShowProfilePhoto;
  final bool privacyShowStatus;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.about,
    this.fcmTokens = const [],
    this.status = UserStatus.offline,
    this.lastSeen,
    required this.createdAt,
    this.privacyShowLastSeen = true,
    this.privacyShowProfilePhoto = true,
    this.privacyShowStatus = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    List<String> tokens = [];
    if (json['fcm_tokens'] != null) {
      tokens = List<String>.from(json['fcm_tokens']);
    } else if (json['fcm_token'] != null) {
      // Backward compatibility
      tokens = [json['fcm_token']];
    }

    return AppUser(
      id: json['id'] as String,
      email: json['email']?.toString() ?? '',
      displayName: json['displayName'] ?? json['username'],
      photoUrl: json['photoUrl'] ?? json['avatar_url'],
      about: json['about'],
      fcmTokens: tokens,
      status: UserStatus.values.firstWhere(
        (e) => e.toString() == 'UserStatus.${json['status']}',
        orElse: () => UserStatus.offline,
      ),
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      privacyShowLastSeen: json['privacy_show_last_seen'] ?? true,
      privacyShowProfilePhoto: json['privacy_show_profile_photo'] ?? true,
      privacyShowStatus: json['privacy_show_status'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': displayName,
      'avatar_url': photoUrl,
      'about': about,
      'fcm_tokens': fcmTokens,
      'status': status.toString().split('.').last,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'privacy_show_last_seen': privacyShowLastSeen,
      'privacy_show_profile_photo': privacyShowProfilePhoto,
      'privacy_show_status': privacyShowStatus,
    };
  }

  AppUser copyWith({
    String? displayName,
    String? photoUrl,
    String? about,
    List<String>? fcmTokens,
    UserStatus? status,
    DateTime? lastSeen,
    bool? privacyShowLastSeen,
    bool? privacyShowProfilePhoto,
    bool? privacyShowStatus,
  }) {
    return AppUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      about: about ?? this.about,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
      privacyShowLastSeen: privacyShowLastSeen ?? this.privacyShowLastSeen,
      privacyShowProfilePhoto:
          privacyShowProfilePhoto ?? this.privacyShowProfilePhoto,
      privacyShowStatus: privacyShowStatus ?? this.privacyShowStatus,
    );
  }

  String get initials {
    if (displayName == null || displayName!.isEmpty) {
      return email[0].toUpperCase();
    }
    final parts = displayName!.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  String get statusText => status.name;
}
