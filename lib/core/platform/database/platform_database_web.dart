import 'platform_database.dart';

/// Web implementation of the database (Stub or IndexedDB based).
/// For now, we return a virtual path since sqflite doesn't support Web directly
/// without additional setup like sqflite_common_ffi_web.
class WebDatabase implements PlatformDatabase {
  @override
  Future<void> initialize() async {
    // No-op for now, or initialize IndexedDB if needed.
  }

  @override
  Future<String> getDatabasePath(String name) async {
    return name; // Virtual path
  }
}

PlatformDatabase getPlatformDatabase() => WebDatabase();
