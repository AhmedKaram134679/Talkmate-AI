import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:talkmate_ai/data/services/messaging_service.dart';
import 'platform_notifications_interface.dart';

class WebNotifications implements IPlatformNotifications {
  @override
  Future<void> initialize() async {
    await MessagingService.instance.initialize();
    unawaited(MessagingService.instance.registerWebPush());
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<void> setBadgeCount(int count) async {
    // Web badges are typically handled via the manifest or JS interop
  }
}

IPlatformNotifications getPlatformNotifications() => WebNotifications();
