import 'dart:async';

/// Abstract interface for platform-specific notification handlers.
abstract class IPlatformNotifications {
  /// Initializes notification services (FCM, Local, Web Push).
  Future<void> initialize();

  /// Requests permission from the user.
  Future<bool> requestPermission();

  /// Sets the badge count on the app icon (if supported).
  Future<void> setBadgeCount(int count);
}
