export 'platform_notifications_interface.dart';
export 'platform_notifications_stub.dart'
    if (dart.library.io) 'platform_notifications_mobile.dart'
    if (dart.library.html) 'platform_notifications_web.dart';
