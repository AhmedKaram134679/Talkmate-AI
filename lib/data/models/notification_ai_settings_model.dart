class NotificationAiSettings {
  final String id;
  final String userId;
  final bool isEnabled;
  final bool adaptiveMode;
  final double sensitivity;
  final String? preferredDigestTime;
  final bool isSafeMode;
  final DateTime? pausedUntil;
  final bool learningEnabled;
  final double systemTrustIndex;
  final bool sandboxModeEnabled;
  final String? weightVersionId;
  final double stabilityScore;

  NotificationAiSettings({
    required this.id,
    required this.userId,
    this.isEnabled = false,
    this.adaptiveMode = true,
    this.sensitivity = 0.5,
    this.preferredDigestTime,
    this.isSafeMode = false,
    this.pausedUntil,
    this.learningEnabled = true,
    this.systemTrustIndex = 1.0,
    this.sandboxModeEnabled = false,
    this.weightVersionId,
    this.stabilityScore = 1.0,
  });

  factory NotificationAiSettings.fromJson(Map<String, dynamic> json) {
    return NotificationAiSettings(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      isEnabled: json['is_enabled'] ?? false,
      adaptiveMode: json['adaptive_mode'] ?? true,
      sensitivity: (json['sensitivity'] as num? ?? 0.5).toDouble(),
      preferredDigestTime: json['preferred_digest_time'],
      isSafeMode: json['is_safe_mode'] ?? false,
      pausedUntil: json['paused_until'] != null
          ? DateTime.parse(json['paused_until'])
          : null,
      learningEnabled: json['learning_enabled'] ?? true,
      systemTrustIndex: (json['system_trust_index'] as num? ?? 1.0).toDouble(),
      sandboxModeEnabled: json['sandbox_mode_enabled'] ?? false,
      weightVersionId: json['weight_version_id'],
      stabilityScore: (json['stability_score'] as num? ?? 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_enabled': isEnabled,
      'adaptive_mode': adaptiveMode,
      'sensitivity': sensitivity,
      'preferred_digest_time': preferredDigestTime,
      'is_safe_mode': isSafeMode,
      'paused_until': pausedUntil?.toIso8601String(),
      'learning_enabled': learningEnabled,
      'system_trust_index': systemTrustIndex,
      'sandbox_mode_enabled': sandboxModeEnabled,
      'weight_version_id': weightVersionId,
      'stability_score': stabilityScore,
    };
  }

  NotificationAiSettings copyWith({
    bool? isEnabled,
    bool? adaptiveMode,
    double? sensitivity,
    String? preferredDigestTime,
    bool? isSafeMode,
    DateTime? pausedUntil,
    bool? learningEnabled,
    double? systemTrustIndex,
    bool? sandboxModeEnabled,
    String? weightVersionId,
    double? stabilityScore,
  }) {
    return NotificationAiSettings(
      id: id,
      userId: userId,
      isEnabled: isEnabled ?? this.isEnabled,
      adaptiveMode: adaptiveMode ?? this.adaptiveMode,
      sensitivity: sensitivity ?? this.sensitivity,
      preferredDigestTime: preferredDigestTime ?? this.preferredDigestTime,
      isSafeMode: isSafeMode ?? this.isSafeMode,
      pausedUntil: pausedUntil ?? this.pausedUntil,
      learningEnabled: learningEnabled ?? this.learningEnabled,
      systemTrustIndex: systemTrustIndex ?? this.systemTrustIndex,
      sandboxModeEnabled: sandboxModeEnabled ?? this.sandboxModeEnabled,
      weightVersionId: weightVersionId ?? this.weightVersionId,
      stabilityScore: stabilityScore ?? this.stabilityScore,
    );
  }
}
