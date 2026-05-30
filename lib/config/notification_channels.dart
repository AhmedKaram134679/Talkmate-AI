import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationChannels {
  // Channel IDs
  static const String messageChannelId = 'chat_messages';
  static const String callChannelId = 'calls_channel';
  static const String systemChannelId = 'system_channel';

  // Message Channel (High Importance, Standard Sound)
  static const AndroidNotificationChannel messageChannel =
      AndroidNotificationChannel(
    messageChannelId,
    'Chat Messages',
    description: 'Direct chat message notifications',
    importance: Importance.high,
    enableVibration: true,
    playSound: true,
    showBadge: true, // Enable badge for messages
  );

  // Call Channel (Max Importance, Silent for AppAudioService control)
  static final AndroidNotificationChannel callChannel =
      AndroidNotificationChannel(
    'calls_channel_silent_v1', // [STRICT_FIX]: New ID to force fresh config
    'Incoming Calls (Silent)',
    description: 'Silent notifications for incoming calls',
    importance: Importance.max,
    enableVibration: true,
    playSound: false, // [STRICT_FIX]: strictly silent
    vibrationPattern:
        Int64List.fromList([0, 1000, 500, 1000]), // Long vibrations
  );

  // System Channel (Low Importance, Silent/Short)
  static const AndroidNotificationChannel systemChannel =
      AndroidNotificationChannel(
    systemChannelId,
    'System Notifications',
    description: 'General system updates and alerts',
    importance: Importance.low,
    enableVibration: false,
    playSound: false,
    showBadge: true, // Also allow badges for system alerts if needed
  );

  // Legacy / Fallback IDs (Stage X Compatibility)
  static const String legacyHighChannelId = 'high_importance_channel';
  static const String alternateMessageChannelId = 'talkmate_messages';

  static final List<AndroidNotificationChannel> all = [
    messageChannel,
    callChannel,
    systemChannel,
    // Add these for safety so OS always finds a registered channel
    const AndroidNotificationChannel(
      legacyHighChannelId,
      'Notifications (Priority)',
      importance: Importance.high,
    ),
    const AndroidNotificationChannel(
      alternateMessageChannelId,
      'TalkMate Messages',
      importance: Importance.high,
    ),
  ];
}
