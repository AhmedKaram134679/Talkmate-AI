class LearningWeights {
  final String userId;
  final double engagementWeight;
  final double contextWeight;
  final double urgencyWeight;
  final double trustScore;
  final int learningCycles;
  final DateTime lastUpdated;

  LearningWeights({
    required this.userId,
    this.engagementWeight = 0.4,
    this.contextWeight = 0.3,
    this.urgencyWeight = 0.3,
    this.trustScore = 1.0,
    this.learningCycles = 0,
    required this.lastUpdated,
  });

  factory LearningWeights.fromJson(Map<String, dynamic> json) {
    return LearningWeights(
      userId: json['user_id'] ?? '',
      engagementWeight: (json['engagement_weight'] as num? ?? 0.4).toDouble(),
      contextWeight: (json['context_weight'] as num? ?? 0.3).toDouble(),
      urgencyWeight: (json['urgency_weight'] as num? ?? 0.3).toDouble(),
      trustScore: (json['trust_score'] as num? ?? 1.0).toDouble(),
      learningCycles: json['learning_cycles'] ?? 0,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'engagement_weight': engagementWeight,
      'context_weight': contextWeight,
      'urgency_weight': urgencyWeight,
      'trust_score': trustScore,
      'learning_cycles': learningCycles,
    };
  }
}

class UserFeedback {
  final String? id;
  final String userId;
  final String decisionId;
  final String feedbackType; // 'positive', 'negative'
  final String? comment;
  final DateTime? createdAt;

  UserFeedback({
    this.id,
    required this.userId,
    required this.decisionId,
    required this.feedbackType,
    this.comment,
    this.createdAt,
  });

  factory UserFeedback.fromJson(Map<String, dynamic> json) {
    return UserFeedback(
      id: json['id'],
      userId: json['user_id'] ?? '',
      decisionId: json['decision_id'] ?? '',
      feedbackType: json['feedback_type'] ?? 'positive',
      comment: json['comment'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'decision_id': decisionId,
      'feedback_type': feedbackType,
      'comment': comment,
    };
  }
}
