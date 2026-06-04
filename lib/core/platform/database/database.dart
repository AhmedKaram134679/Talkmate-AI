export 'platform_database.dart';
export 'platform_database_stub.dart'
    if (dart.library.io) 'platform_database_mobile.dart'
    if (dart.library.html) 'platform_database_web.dart';
