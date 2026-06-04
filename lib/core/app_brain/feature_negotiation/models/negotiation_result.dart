enum NegotiationDecision {
  approve,
  degrade,
  delay,
  reject,
}

/// The outcome of an arbitration.
class NegotiationResult {
  final String featureId;
  final NegotiationDecision decision;
  final Map<String, dynamic> finalConstraints;
  final String reason;

  NegotiationResult({
    required this.featureId,
    required this.decision,
    this.finalConstraints = const {},
    this.reason = '',
  });

  factory NegotiationResult.approved(String id) =>
      NegotiationResult(featureId: id, decision: NegotiationDecision.approve);

  factory NegotiationResult.rejected(String id, String reason) =>
      NegotiationResult(
          featureId: id, decision: NegotiationDecision.reject, reason: reason);

  @override
  String toString() => 'Result($featureId, ${decision.name}, $reason)';
}
