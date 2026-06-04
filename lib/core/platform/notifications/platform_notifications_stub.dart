import 'platform_notifications_interface.dart';

IPlatformNotifications getPlatformNotifications() => throw UnsupportedError(
      'Cannot create a IPlatformNotifications without dart:html or dart:io',
    );
