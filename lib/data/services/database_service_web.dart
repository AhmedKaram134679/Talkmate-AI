import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();

  DatabaseService._init();

  Future<Database> get database async {
    throw UnimplementedError('DatabaseService is not supported on Web');
  }

  Future close() async {}
}
