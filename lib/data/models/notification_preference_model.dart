class NotificationPreference {
  final String id;
  final String userId;
  final bool chatsEnabled;
  final bool groupsEnabled;
  final bool callsEnabled;
  final bool mentionsEnabled;
  final String style;
  final bool dndEnabled;
  final String dndStart;
  final String dndEnd;
  final int timezoneOffset;

  NotificationPreference({
    required this.id,
    required this.userId,
    this.chatsEnabled = true,
    this.groupsEnabled = true,
    this.callsEnabled = true,
    this.mentionsEnabled = true,
    this.style = 'full',
    this.dndEnabled = false,
    this.dndStart = '22:00',
    this.dndEnd = '08:00',
    this.timezoneOffset = 0,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      chatsEnabled: json['chats_enabled'] ?? true,
      groupsEnabled: json['groups_enabled'] ?? true,
      callsEnabled: json['calls_enabled'] ?? true,
      mentionsEnabled: json['mentions_enabled'] ?? true,
      style: json['pref_style'] ?? 'full',
      dndEnabled: json['dnd_enabled'] ?? false,
      dndStart: json['dnd_start'] ?? '22:00',
      dndEnd: json['dnd_end'] ?? '08:00',
      timezoneOffset: json['timezone_offset'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chats_enabled': chatsEnabled,
      'groups_enabled': groupsEnabled,
      'calls_enabled': callsEnabled,
      'mentions_enabled': mentionsEnabled,
      'pref_style': style,
      'dnd_enabled': dndEnabled,
      'dnd_start': dndStart,
      'dnd_end': dndEnd,
      'timezone_offset': timezoneOffset,
    };
  }

  NotificationPreference copyWith({
    bool? chatsEnabled,
    bool? groupsEnabled,
    bool? callsEnabled,
    bool? mentionsEnabled,
    String? style,
    bool? dndEnabled,
    String? dndStart,
    String? dndEnd,
    int? timezoneOffset,
  }) {
    return NotificationPreference(
      id: id,
      userId: userId,
      chatsEnabled: chatsEnabled ?? this.chatsEnabled,
      groupsEnabled: groupsEnabled ?? this.groupsEnabled,
      callsEnabled: callsEnabled ?? this.callsEnabled,
      mentionsEnabled: mentionsEnabled ?? this.mentionsEnabled,
      style: style ?? this.style,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      dndStart: dndStart ?? this.dndStart,
      dndEnd: dndEnd ?? this.dndEnd,
      timezoneOffset: timezoneOffset ?? this.timezoneOffset,
    );
  }
}
