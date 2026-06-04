class RoutingLogModel {
  final String id;
  final String deviceId;
  final String decision; // sent, silent, skipped
  final String? priority;
  final String? reason;
  final Map<String, dynamic> meta;
  final DateTime createdAt;

  RoutingLogModel({
    required this.id,
    required this.deviceId,
    required this.decision,
    this.priority,
    this.reason,
    required this.meta,
    required this.createdAt,
  });

  factory RoutingLogModel.fromJson(Map<String, dynamic> json) {
    return RoutingLogModel(
      id: json['id'],
      deviceId: json['device_id'] ?? 'Unknown',
      decision: json['decision'] ?? 'unknown',
      priority: json['priority'],
      reason: json['reason'],
      meta: json['meta'] ?? {},
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }
}
