class DeviceAnalyticsModel {
  final String deviceId;
  final int totalSent;
  final int totalDelivered;
  final int totalRead;

  DeviceAnalyticsModel({
    required this.deviceId,
    required this.totalSent,
    required this.totalDelivered,
    required this.totalRead,
  });

  factory DeviceAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return DeviceAnalyticsModel(
      deviceId: json['device_id'] ?? 'Unknown',
      totalSent: json['total_sent'] ?? 0,
      totalDelivered: json['total_delivered'] ?? 0,
      totalRead: json['total_read'] ?? 0,
    );
  }

  double get deliveryRate =>
      totalSent == 0 ? 0.0 : (totalDelivered / totalSent);

  double get readRate =>
      totalDelivered == 0 ? 0.0 : (totalRead / totalDelivered);
}
