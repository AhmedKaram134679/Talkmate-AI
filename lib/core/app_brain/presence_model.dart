import 'package:flutter/foundation.dart';

/// BrainPresence: An enhanced model for user availability and device context.
@immutable
class BrainPresence {
  final String userId;
  final bool isOnline;
  final String lastActiveDevice;
  final DeviceEngagement engagement;
  final Map<String, dynamic>
      capabilities; // e.g., {'video': true, 'ai_assisted': false}

  const BrainPresence({
    required this.userId,
    required this.isOnline,
    required this.lastActiveDevice,
    this.engagement = DeviceEngagement.idle,
    this.capabilities = const {},
  });

  BrainPresence copyWith({
    bool? isOnline,
    String? lastActiveDevice,
    DeviceEngagement? engagement,
    Map<String, dynamic>? capabilities,
  }) {
    return BrainPresence(
      userId: userId,
      isOnline: isOnline ?? this.isOnline,
      lastActiveDevice: lastActiveDevice ?? this.lastActiveDevice,
      engagement: engagement ?? this.engagement,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}

/// DeviceEngagement: Level of active interaction on a specific device.
enum DeviceEngagement {
  idle, // App in background or screen off
  active, // App in foreground, browsing
  busy, // In a call or composing long message
  doNotDisturb, // Explicit status set by user
}
