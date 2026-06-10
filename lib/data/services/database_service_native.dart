import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('talkmate_core.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
CREATE TABLE local_sync_actions (
  id TEXT PRIMARY KEY,
  action_type TEXT NOT NULL,
  chat_id TEXT,
  payload TEXT,
  created_at TEXT NOT NULL
)
''');
      await db.execute(
          'CREATE INDEX idx_sync_actions_created ON local_sync_actions(created_at)');
    }
    
    // Migration V3: Add media tracking fields (VIDEO_TRACE_DB_SAVE)
    if (oldVersion < 3) {
      try {
        // Check if columns already exist before adding them
        final columns = await db.rawQuery('PRAGMA table_info(local_messages)');
        final columnNames = (columns as List).map((col) => col['name'] as String).toList();
        
        if (!columnNames.contains('local_file_path')) {
          await db.execute('ALTER TABLE local_messages ADD COLUMN local_file_path TEXT');
        }
        if (!columnNames.contains('original_file_name')) {
          await db.execute('ALTER TABLE local_messages ADD COLUMN original_file_name TEXT');
        }
        if (!columnNames.contains('upload_progress')) {
          await db.execute('ALTER TABLE local_messages ADD COLUMN upload_progress REAL DEFAULT 0.0');
        }
      } catch (e) {
        // Columns might already exist, silently continue
      }
    }
  }

  Future _createDB(Database db, int version) async {
    // Stage Core: Local Messages Table
    await db.execute('''
CREATE TABLE local_messages (
  local_id TEXT PRIMARY KEY,
  id TEXT,
  chat_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  type TEXT NOT NULL,
  content TEXT,
  media_url TEXT,
  thumbnail_url TEXT,
  media_size INTEGER,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  reply_to_message_id TEXT,
  metadata TEXT,
  local_file_path TEXT,
  original_file_name TEXT,
  upload_progress REAL DEFAULT 0.0
)
''');

    await db.execute(
        'CREATE INDEX idx_local_messages_chat_id ON local_messages(chat_id)');
    await db.execute(
        'CREATE INDEX idx_local_messages_status ON local_messages(status)');

    // Stage U: Sync Actions Table
    await db.execute('''
CREATE TABLE local_sync_actions (
  id TEXT PRIMARY KEY,
  action_type TEXT NOT NULL,
  chat_id TEXT,
  payload TEXT,
  created_at TEXT NOT NULL
)
''');
    await db.execute(
        'CREATE INDEX idx_sync_actions_created ON local_sync_actions(created_at)');
  }

  Future close() async {
    final db = await instance.database;
    unawaited(db.close());
  }
}
