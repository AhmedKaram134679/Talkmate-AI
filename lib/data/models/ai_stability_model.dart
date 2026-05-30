class LearningWeightSnapshot {
  final String id;
  final String userId;
  final double engagementWeight;
  final double contextWeight;
  final double urgencyWeight;
  final double trustScore;
  final String? versionTag;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  LearningWeightSnapshot({
    required this.id,
    required this.userId,
    required this.engagementWeight,
    required this.contextWeight,
    required this.urgencyWeight,
    required this.trustScore,
    this.versionTag,
    this.metadata = const {},
    required this.createdAt,
  });

  factory LearningWeightSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningWeightSnapshot(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      engagementWeight: (json['engagement_weight'] as num? ?? 0.0).toDouble(),
      contextWeight: (json['context_weight'] as num? ?? 0.0).toDouble(),
      urgencyWeight: (json['urgency_weight'] as num? ?? 0.0).toDouble(),
      trustScore: (json['trust_score'] as num? ?? 0.0).toDouble(),
      versionTag: json['version_tag'],
      metadata: json['metadata'] ?? {},
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class GovernanceAudit {
  final String id;
  final String userId;
  final String actionType;
  final Map<String, dynamic> details;
  final String severity;
  final DateTime createdAt;

  GovernanceAudit({
    required this.id,
    required this.userId,
    required this.actionType,
    required this.details,
    this.severity = 'info',
    required this.createdAt,
  });

  factory GovernanceAudit.fromJson(Map<String, dynamic> json) {
    return GovernanceAudit(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      actionType: json['action_type'] ?? '',
      details: json['details'] ?? {},
      severity: json['severity'] ?? 'info',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
