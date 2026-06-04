class UserContextSettings {
  final String userId;
  final bool predictiveTimingEnabled;
  final bool respectDrivingMode;
  final double nightModeSensitivity;
  final double workHoursSensitivity;
  final double contextWeight;

  UserContextSettings({
    required this.userId,
    this.predictiveTimingEnabled = true,
    this.respectDrivingMode = true,
    this.nightModeSensitivity = 0.8,
    this.workHoursSensitivity = 0.5,
    this.contextWeight = 0.5,
  });

  factory UserContextSettings.fromJson(Map<String, dynamic> json) {
    return UserContextSettings(
      userId: json['user_id'],
      predictiveTimingEnabled: json['predictive_timing_enabled'] ?? true,
      respectDrivingMode: json['respect_driving_mode'] ?? true,
      nightModeSensitivity:
          (json['night_mode_sensitivity'] as num? ?? 0.8).toDouble(),
      workHoursSensitivity:
          (json['work_hours_sensitivity'] as num? ?? 0.5).toDouble(),
      contextWeight: (json['context_weight'] as num? ?? 0.5).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'predictive_timing_enabled': predictiveTimingEnabled,
      'respect_driving_mode': respectDrivingMode,
      'night_mode_sensitivity': nightModeSensitivity,
      'work_hours_sensitivity': workHoursSensitivity,
      'context_weight': contextWeight,
    };
  }

  UserContextSettings copyWith({
    bool? predictiveTimingEnabled,
    bool? respectDrivingMode,
    double? nightModeSensitivity,
    double? workHoursSensitivity,
    double? contextWeight,
  }) {
    return UserContextSettings(
      userId: userId,
      predictiveTimingEnabled:
          predictiveTimingEnabled ?? this.predictiveTimingEnabled,
      respectDrivingMode: respectDrivingMode ?? this.respectDrivingMode,
      nightModeSensitivity: nightModeSensitivity ?? this.nightModeSensitivity,
      workHoursSensitivity: workHoursSensitivity ?? this.workHoursSensitivity,
      contextWeight: contextWeight ?? this.contextWeight,
    );
  }
}

class UserContextProfile {
  final String userId;
  final Map<String, dynamic> activityMap;
  final List<int> peakInteractionHours;

  UserContextProfile({
    required this.userId,
    required this.activityMap,
    required this.peakInteractionHours,
  });

  factory UserContextProfile.fromJson(Map<String, dynamic> json) {
    return UserContextProfile(
      userId: json['user_id'],
      activityMap: json['activity_map'] ?? {},
      peakInteractionHours:
          List<int>.from(json['peak_interaction_hours'] ?? []),
    );
  }
}
