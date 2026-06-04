import 'dart:async';

/// Abstract interface for handling files across platforms.
/// Native platforms use dart:io File, Web uses simplified byte handling.
abstract class IPlatformStorage {
  /// Gets the platform-specific directory for application data.
  Future<String> getAppDataDirectory();

  /// Deletes a file safely across platforms.
  Future<void> deleteFile(String path);

  /// Checks if a file exists.
  Future<bool> fileExists(String path);
}
