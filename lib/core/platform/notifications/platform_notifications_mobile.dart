import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:talkmate_ai/data/services/messaging_service.dart';
import 'platform_notifications_interface.dart';

class MobileNotifications implements IPlatformNotifications {
  @override
  Future<void> initialize() async {
    // Native FCM and Local Notifications setup
    await MessagingService.instance.initialize();
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<void> setBadgeCount(int count) async {
    // Legacy badge control was removed but we can add native implementations here
    // or use a cross-platform package if re-introduced safely.
  }
}

IPlatformNotifications getPlatformNotifications() => MobileNotifications();
