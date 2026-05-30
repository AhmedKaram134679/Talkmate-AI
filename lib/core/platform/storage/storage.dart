export 'platform_storage_interface.dart';
export 'platform_storage_stub.dart'
    if (dart.library.io) 'platform_storage_mobile.dart'
    if (dart.library.html) 'platform_storage_web.dart';
