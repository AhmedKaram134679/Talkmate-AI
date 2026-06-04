import 'dart:async';

/// Abstract interface for platform-specific database initialization.
/// This allows us to use SQLite (FFI) on Desktop/Mobile and IndexedDB/Stub on Web.
abstract class PlatformDatabase {
  /// Initializes the database engine for the current platform.
  Future<void> initialize();

  /// Gets the path where the database file is stored (native platforms)
  /// or a virtual path (web).
  Future<String> getDatabasePath(String name);
}
