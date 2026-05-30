/// A request submitted to the Negotiation Engine.
class NegotiationRequest {
  final String featureId;
  final String action;
  final int resourceCost; // 1-10 (10 = Heavy CPU/Network)
  final Map<String, dynamic> desiredConstraints;
  final DateTime timestamp;

  NegotiationRequest({
    required this.featureId,
    required this.action,
    this.resourceCost = 1,
    this.desiredConstraints = const {},
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'Req($featureId, $action, cost=$resourceCost)';
}
