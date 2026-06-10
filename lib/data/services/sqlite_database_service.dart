import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite Database Service for media system persistence
/// Handles: pending uploads, cached media, audio playback state, failed uploads
class SqliteDatabaseService {
  static final SqliteDatabaseService _instance =
      SqliteDatabaseService._internal();

  factory SqliteDatabaseService() => _instance;

  SqliteDatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'talkmate_media.db');

    return openDatabase(
      path,
      version: 6,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
            'ALTER TABLE pending_uploads ADD COLUMN chat_id TEXT DEFAULT ""');
        await db.execute(
            'ALTER TABLE pending_uploads ADD COLUMN user_id TEXT DEFAULT ""');
        await db.execute(
            'ALTER TABLE pending_uploads ADD COLUMN upload_path TEXT DEFAULT ""');
      } catch (e) {
        debugPrint('Migration pending_uploads columns warning: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE failed_uploads ADD COLUMN chat_id TEXT DEFAULT ""');
        await db.execute(
            'ALTER TABLE failed_uploads ADD COLUMN user_id TEXT DEFAULT ""');
        await db.execute(
            'ALTER TABLE failed_uploads ADD COLUMN upload_path TEXT DEFAULT ""');
        await db.execute(
            'ALTER TABLE failed_uploads ADD COLUMN media_type TEXT DEFAULT ""');
      } catch (e) {
        debugPrint('Migration failed_uploads columns warning: $e');
      }
    }
    if (oldVersion < 3) {
      debugPrint(
          '🚀 [SqliteDatabaseService] Migrating to version 3: Adding media_states table');
      await db.execute('''
        CREATE TABLE media_states (
          message_id TEXT PRIMARY KEY,
          local_path TEXT,
          remote_url TEXT,
          upload_status TEXT NOT NULL,
          upload_task_id TEXT,
          last_known_progress REAL DEFAULT 0.0,
          timestamp INTEGER NOT NULL,
          error_message TEXT
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_media_states_status ON media_states(upload_status)');
    }
    if (oldVersion < 4) {
      debugPrint(
          '🚀 [SqliteDatabaseService] Migrating to version 4: Adding file_name and media_type to media_states');
      try {
        await db.execute('ALTER TABLE media_states ADD COLUMN file_name TEXT');
        await db.execute('ALTER TABLE media_states ADD COLUMN media_type TEXT');
      } catch (e) {
        debugPrint('Migration media_states file_name/media_type warning: $e');
      }
    }
    if (oldVersion < 5) {
      debugPrint(
          '🚀 [SqliteDatabaseService] Migrating to version 5: Adding thumbnail_path to media_states');
      try {
        await db.execute('ALTER TABLE media_states ADD COLUMN thumbnail_path TEXT');
      } catch (e) {
        debugPrint('Migration media_states thumbnail_path warning: $e');
      }
    }
    if (oldVersion < 6) {
      debugPrint(
          '🚀 [SqliteDatabaseService] Migrating to version 6: Adding remote_thumbnail_url to media_states');
      try {
        await db.execute('ALTER TABLE media_states ADD COLUMN remote_thumbnail_url TEXT');
      } catch (e) {
        debugPrint('Migration media_states remote_thumbnail_url warning: $e');
      }
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE media_states (
        message_id TEXT PRIMARY KEY,
        local_path TEXT,
        remote_url TEXT,
        upload_status TEXT NOT NULL,
        upload_task_id TEXT,
        last_known_progress REAL DEFAULT 0.0,
        timestamp INTEGER NOT NULL,
        error_message TEXT,
        file_name TEXT,
        media_type TEXT,
        thumbnail_path TEXT,
        remote_thumbnail_url TEXT
      )
    ''');

    // Pending uploads table
    await db.execute('''
      CREATE TABLE pending_uploads (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        chat_id TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        upload_path TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        upload_status TEXT NOT NULL,
        upload_progress REAL DEFAULT 0.0,
        retry_count INTEGER DEFAULT 0,
        last_retry_time INTEGER,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Cached media table
    await db.execute('''
      CREATE TABLE cached_media (
        id TEXT PRIMARY KEY,
        original_url TEXT NOT NULL UNIQUE,
        local_file_path TEXT NOT NULL,
        media_type TEXT NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        cache_created_at INTEGER NOT NULL,
        cache_expires_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL
      )
    ''');

    // Audio playback state table
    await db.execute('''
      CREATE TABLE audio_playback_state (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        current_position_ms INTEGER DEFAULT 0,
        duration_ms INTEGER DEFAULT 0,
        playback_speed REAL DEFAULT 1.0,
        is_listened INTEGER DEFAULT 0,
        last_updated INTEGER NOT NULL
      )
    ''');

    // Failed uploads table
    await db.execute('''
      CREATE TABLE failed_uploads (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        chat_id TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        upload_path TEXT NOT NULL DEFAULT '',
        media_type TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL,
        failure_reason TEXT NOT NULL,
        retry_attempts_left INTEGER DEFAULT 3,
        created_at INTEGER NOT NULL
      )
    ''');

    // Create indexes for faster queries
    await db.execute(
        'CREATE INDEX idx_pending_uploads_status ON pending_uploads(upload_status)');
    await db.execute(
        'CREATE INDEX idx_cached_media_expires ON cached_media(cache_expires_at)');
  }

  // Pending Uploads Operations
  Future<void> insertPendingUpload({
    required String id,
    required String messageId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String mediaType,
    required String chatId,
    required String userId,
    required String uploadPath,
  }) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_PENDING_UPLOAD_INSERT: taskId=$id, messageId=$messageId, fileName=$fileName, fileSize=$fileSize, path=$filePath');
    final db = await database;
    await db.insert(
      'pending_uploads',
      {
        'id': id,
        'message_id': messageId,
        'chat_id': chatId,
        'user_id': userId,
        'upload_path': uploadPath,
        'file_path': filePath,
        'file_name': fileName,
        'file_size': fileSize,
        'media_type': mediaType,
        'upload_status': 'pending',
        'upload_progress': 0.0,
        'retry_count': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUploadProgress(String id, double progress) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_PENDING_UPLOAD_UPDATE: taskId=$id, progress=$progress');
    final db = await database;
    await db.update(
      'pending_uploads',
      {
        'upload_progress': progress,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateUploadStatus(String id, String status,
      {String? errorMessage}) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_PENDING_UPLOAD_UPDATE: taskId=$id, status=$status');
    final db = await database;
    final update = {
      'upload_status': status,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (errorMessage != null) {
      update['error_message'] = errorMessage;
    }

    await db.update(
      'pending_uploads',
      update,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementRetryCount(String id) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_PENDING_UPLOAD_UPDATE: taskId=$id, action=incrementRetry');
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_uploads SET retry_count = retry_count + 1, last_retry_time = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingUploads() async {
    final db = await database;

    final pending = await db.query(
      'pending_uploads',
      where: 'upload_status = ? OR upload_status = ?',
      whereArgs: ['uploading', 'pending'],
      orderBy: 'created_at ASC',
    );

    final failed = await db.query('failed_uploads');

    debugPrint(
        '📊 [SqliteDatabaseService] DB_UPLOAD_AUDIT: pending_uploads=${pending.length}, failed_uploads=${failed.length}');

    return pending;
  }

  Future<void> deletePendingUpload(String id) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_PENDING_UPLOAD_DELETE: taskId=$id');
    final db = await database;
    await db.delete(
      'pending_uploads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Cached Media Operations
  Future<void> insertCachedMedia({
    required String id,
    required String originalUrl,
    required String localFilePath,
    required String mediaType,
    required int fileSizeBytes,
    required DateTime expiresAt,
  }) async {
    final db = await database;
    await db.insert(
      'cached_media',
      {
        'id': id,
        'original_url': originalUrl,
        'local_file_path': localFilePath,
        'media_type': mediaType,
        'file_size_bytes': fileSizeBytes,
        'cache_created_at': DateTime.now().millisecondsSinceEpoch,
        'cache_expires_at': expiresAt.millisecondsSinceEpoch,
        'last_accessed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedMedia(String originalUrl) async {
    final db = await database;
    final result = await db.query(
      'cached_media',
      where: 'original_url = ?',
      whereArgs: [originalUrl],
    );

    if (result.isNotEmpty) {
      // Update last accessed time
      await db.update(
        'cached_media',
        {'last_accessed_at': DateTime.now().millisecondsSinceEpoch},
        where: 'original_url = ?',
        whereArgs: [originalUrl],
      );
      return result.first;
    }
    return null;
  }

  Future<void> cleanExpiredCache() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete(
      'cached_media',
      where: 'cache_expires_at < ?',
      whereArgs: [now],
    );
  }

  Future<int> getCacheSizeBytes() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(file_size_bytes) as total_size FROM cached_media');
    final totalSize = (result.first['total_size'] as int?) ?? 0;
    return totalSize;
  }

  // Audio Playback State Operations
  Future<void> updateAudioPlaybackState({
    required String messageId,
    required int currentPositionMs,
    required int durationMs,
    required double playbackSpeed,
    required bool isListened,
  }) async {
    final db = await database;
    await db.insert(
      'audio_playback_state',
      {
        'id': 'audio_$messageId',
        'message_id': messageId,
        'current_position_ms': currentPositionMs,
        'duration_ms': durationMs,
        'playback_speed': playbackSpeed,
        'is_listened': isListened ? 1 : 0,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getAudioPlaybackState(String messageId) async {
    final db = await database;
    final result = await db.query(
      'audio_playback_state',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // Failed Uploads Operations
  Future<void> insertFailedUpload({
    required String id,
    required String messageId,
    required String filePath,
    required String failureReason,
    String chatId = '',
    String userId = '',
    String uploadPath = '',
    String mediaType = '',
    int retryAttemptsLeft = 3,
  }) async {
    final db = await database;
    await db.insert(
      'failed_uploads',
      {
        'id': id,
        'message_id': messageId,
        'chat_id': chatId,
        'user_id': userId,
        'upload_path': uploadPath,
        'media_type': mediaType,
        'file_path': filePath,
        'failure_reason': failureReason,
        'retry_attempts_left': retryAttemptsLeft,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getFailedUploads() async {
    final db = await database;
    return db.query(
      'failed_uploads',
      where: 'retry_attempts_left > 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<void> decrementFailedUploadRetries(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE failed_uploads SET retry_attempts_left = retry_attempts_left - 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> deleteFailedUpload(String id) async {
    final db = await database;
    await db.delete(
      'failed_uploads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Media State Operations
  Future<void> saveMediaState(Map<String, dynamic> stateMap) async {
    debugPrint(
        '💾 [SqliteDatabaseService] DB_MEDIA_STATE_SAVE: messageId=${stateMap['message_id']}');
    final db = await database;
    await db.insert(
      'media_states',
      stateMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getMediaState(String messageId) async {
    final db = await database;
    final results = await db.query(
      'media_states',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllMediaStates() async {
    final db = await database;
    return await db.query('media_states', orderBy: 'timestamp DESC');
  }

  Future<void> deleteMediaState(String messageId) async {
    final db = await database;
    await db.delete(
      'media_states',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
