class NotificationExperiencePrefs {
  final String userId;
  final String experienceMode; // 'critical', 'smart', 'all'
  final bool isSnoozed;
  final DateTime? snoozeUntil;
  final int maxHourlyNotifications;
  final List<String> categoryDenylist;
  final DateTime? updatedAt;

  NotificationExperiencePrefs({
    required this.userId,
    this.experienceMode = 'smart',
    this.isSnoozed = false,
    this.snoozeUntil,
    this.maxHourlyNotifications = 20,
    this.categoryDenylist = const [],
    this.updatedAt,
  });

  factory NotificationExperiencePrefs.fromJson(Map<String, dynamic> json) {
    return NotificationExperiencePrefs(
      userId: json['user_id'] ?? '',
      experienceMode: json['experience_mode'] ?? 'smart',
      isSnoozed: json['is_snoozed'] ?? false,
      snoozeUntil: json['snooze_until'] != null
          ? DateTime.parse(json['snooze_until'])
          : null,
      maxHourlyNotifications: json['max_hourly_notifications'] ?? 20,
      categoryDenylist: List<String>.from(json['category_denylist'] ?? []),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'experience_mode': experienceMode,
      'is_snoozed': isSnoozed,
      'snooze_until': snoozeUntil?.toIso8601String(),
      'max_hourly_notifications': maxHourlyNotifications,
      'category_denylist': categoryDenylist,
    };
  }

  NotificationExperiencePrefs copyWith({
    String? experienceMode,
    bool? isSnoozed,
    DateTime? snoozeUntil,
    int? maxHourlyNotifications,
    List<String>? categoryDenylist,
    DateTime? updatedAt,
  }) {
    return NotificationExperiencePrefs(
      userId: userId,
      experienceMode: experienceMode ?? this.experienceMode,
      isSnoozed: isSnoozed ?? this.isSnoozed,
      snoozeUntil: snoozeUntil ?? this.snoozeUntil,
      maxHourlyNotifications:
          maxHourlyNotifications ?? this.maxHourlyNotifications,
      categoryDenylist: categoryDenylist ?? this.categoryDenylist,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
