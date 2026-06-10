import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

import 'platform_database.dart';

/// Mobile/Desktop implementation of the database initialization.
class MobileDatabase implements PlatformDatabase {
  @override
  Future<void> initialize() async {
    if (Platform.isWindows || Platform.isLinux) {
      if (Platform.isWindows) {
        // Force load sqlite3.dll to avoid "sqlite3.x64.windows.dll not found" error
        sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.windows, () {
          try {
            return DynamicLibrary.open('sqlite3.dll');
          } catch (e) {
            debugPrint('sqlite3.dll load warning: $e');
            try {
              // Try looking in the current directory as fallback
              return DynamicLibrary.open('${Directory.current.path}\\sqlite3.dll');
            } catch (_) {
              // Rethrow the original exception if fallback fails
              rethrow;
            }
          }
        });
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  @override
  Future<String> getDatabasePath(String name) async {
    return await getDatabasesPath();
  }
}

PlatformDatabase getPlatformDatabase() => MobileDatabase();
