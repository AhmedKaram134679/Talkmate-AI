import 'dart:ffi';
import 'dart:io';

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
          } catch (_) {
            // Try looking in current directory as fallback or let it fail naturally
            return DynamicLibrary.open('sqlite3.dll');
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
