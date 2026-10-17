import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _webDb;

  DatabaseService._init();

  Future<Database> get database async {
    if (_webDb != null) return _webDb!;
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    _webDb = await factory.openDatabase(inMemoryDatabasePath);
    return _webDb!;
  }

  Future close() async {
    await _webDb?.close();
    _webDb = null;
  }
}
