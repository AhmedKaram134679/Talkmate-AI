/// Represents the trust level the user has in a specific feature.
class TrustProfile {
  final String featureId;
  double score; // 0.0 - 100.0
  int totalInteractions;
  int rejections;

  TrustProfile({
    required this.featureId,
    this.score = 50.0, // Start Neutral
    this.totalInteractions = 0,
    this.rejections = 0,
  });

  bool get isTrusted => score > 70;
  bool get isUntrusted => score < 30;

  @override
  String toString() => 'Trust($featureId, ${score.toStringAsFixed(1)})';
}
