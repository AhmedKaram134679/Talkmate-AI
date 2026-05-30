class DeviceModel {
  final String deviceId;
  final String? platform;
  final DateTime? lastActiveAt;
  final bool isOnline;
  final String? appState;
  final bool isCurrentDevice;

  DeviceModel({
    required this.deviceId,
    this.platform,
    this.lastActiveAt,
    this.isOnline = false,
    this.appState,
    this.isCurrentDevice = false,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json,
      {String? currentDeviceId}) {
    final devId = json['device_id'] as String? ?? '';
    return DeviceModel(
      deviceId: devId,
      platform: json['platform'] as String?,
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.tryParse(json['last_active_at'].toString())
          : null,
      isOnline: json['is_online'] as bool? ?? false,
      appState: json['app_state'] as String?,
      isCurrentDevice: currentDeviceId != null && currentDeviceId == devId,
    );
  }
}
