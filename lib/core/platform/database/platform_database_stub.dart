import 'platform_database.dart';

/// Stub implementation to prevent compilation errors on platforms where
/// the implementation is not available.
PlatformDatabase getPlatformDatabase() => throw UnsupportedError(
      'Cannot create a PlatformDatabase without dart:html or dart:io',
    );
