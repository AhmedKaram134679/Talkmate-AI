import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:talkmate_ai/core/utils/app_logger.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/models/sync_action_model.dart';

import '../../services/database_service_native.dart';
import '../contracts/i_local_message_repository.dart';

class LocalMessageRepository implements ILocalMessageRepository {
  final DatabaseService _dbService = DatabaseService.instance;
  final Map<String, StreamController<List<Message>>> _controllers = {};

  StreamController<List<Message>> _getController(String chatId) {
    // ignore: close_sinks
    return _controllers.putIfAbsent(
        chatId, () => StreamController<List<Message>>.broadcast());
  }

  Future<void> _notify(String chatId) async {
    if (_controllers.containsKey(chatId)) {
      final messages = await getChatMessages(chatId);
      _controllers[chatId]!.add(messages);
    }
  }

  @override
  Future<void> saveMessage(Message message) async {
    try {
      final db = await _dbService.database;
      final data = {
        'local_id': message.localId ?? message.id,
        'id': message.id,
        'chat_id': message.chatId,
        'sender_id': message.senderId,
        'type': message.type.name,
        'content': message.text,
        'media_url': message.mediaUrl,
        'thumbnail_url': message.thumbnailUrl,
        'media_size': message.mediaSize,
        'status': message.status.name,
        'created_at': message.createdAt.toIso8601String(),
        'reply_to_message_id': message.replyToMessageId,
        'metadata':
            message.reactions != null ? jsonEncode(message.reactions) : null,
        // Media tracking fields - CRITICAL for upload persistence (VIDEO_TRACE_DB_SAVE)
        'local_file_path': message.localFilePath,
        'original_file_name': message.originalFileName,
        'upload_progress': message.uploadProgress,
      };

      debugPrint('VIDEO_TRACE_DB_SAVE: messageId=${message.id}, localId=${message.localId}, fileName=${message.originalFileName}, filePath=${message.localFilePath}, status=${message.status.name}, mediaType=${message.type.name}');

      await db.insert(
        'local_messages',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      unawaited(_notify(message.chatId));
    } catch (e, stack) {
      AppLogger.error('Repository: Failed to save local message',
          context: {
            'chat_id': message.chatId,
            'msg_id': message.id,
            'type': message.type.name
          },
          error: e,
          stackTrace: stack);
      rethrow;
    }
  }

  @override
  Stream<List<Message>> watchChatMessages(String chatId) {
    // ignore: close_sinks
    final controller = _getController(chatId);
    unawaited(_notify(chatId)); // Initial pull
    return controller.stream;
  }

  @override
  Future<List<Message>> getChatMessages(String chatId) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'local_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => _mapToMessage(maps[i]));
  }

  @override
  Future<List<Message>> getPendingMessages() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'local_messages',
      where: 'status = ? OR status = ? OR status = ?',
      whereArgs: [
        MessageStatus.pending.name,
        MessageStatus.failed.name,
        MessageStatus.uploaded.name,
      ],
      orderBy: 'created_at ASC',
    );

    return List.generate(maps.length, (i) => _mapToMessage(maps[i]));
  }

  @override
  Future<void> updateMessageStatus(String localId, MessageStatus status,
      {String? serverId}) async {
    final db = await _dbService.database;
    final data = <String, dynamic>{
      'status': status.name,
    };
    if (serverId != null) {
      data['id'] = serverId;
    }

    final maps = await db.query('local_messages',
        columns: ['chat_id'], where: 'local_id = ?', whereArgs: [localId]);
    final chatId = maps.isNotEmpty ? maps.first['chat_id'] as String : null;

    await db.update(
      'local_messages',
      data,
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (chatId != null) unawaited(_notify(chatId));
  }

  @override
  Future<void> deleteMessage(String localId) async {
    final db = await _dbService.database;
    final maps = await db.query('local_messages',
        columns: ['chat_id'], where: 'local_id = ?', whereArgs: [localId]);
    final chatId = maps.isNotEmpty ? maps.first['chat_id'] as String : null;

    await db.delete(
      'local_messages',
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (chatId != null) unawaited(_notify(chatId));
  }

  @override
  Future<void> clearChat(String chatId) async {
    final db = await _dbService.database;
    await db.delete(
      'local_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
    unawaited(_notify(chatId));
  }

  @override
  Future<void> saveSyncAction(SyncAction action) async {
    final db = await _dbService.database;
    await db.insert('local_sync_actions', action.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<SyncAction>> getPendingSyncActions() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'local_sync_actions',
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) => SyncAction.fromMap(maps[i]));
  }

  @override
  Future<void> deleteSyncAction(String actionId) async {
    final db = await _dbService.database;
    await db.delete(
      'local_sync_actions',
      where: 'id = ?',
      whereArgs: [actionId],
    );
  }

  Message _mapToMessage(Map<String, dynamic> map) {
    final message = Message(
      id: map['id'] as String? ?? map['local_id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      type: MessageType.values.firstWhere((e) => e.name == map['type']),
      text: map['content'] as String?,
      mediaUrl: map['media_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      mediaSize: map['media_size'] as int?,
      status: MessageStatus.values.firstWhere((e) => e.name == map['status']),
      createdAt: DateTime.parse(map['created_at'] as String),
      localId: map['local_id'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      reactions: map['metadata'] != null
          ? Map<String, String>.from(jsonDecode(map['metadata']))
          : null,
      // Media tracking fields - CRITICAL for upload persistence (VIDEO_TRACE_DB_LOAD)
      localFilePath: map['local_file_path'] as String?,
      originalFileName: map['original_file_name'] as String?,
      uploadProgress: map['upload_progress'] != null 
          ? double.tryParse(map['upload_progress'].toString()) ?? 0.0 
          : 0.0,
    );
    
    debugPrint('VIDEO_TRACE_DB_LOAD: messageId=${message.id}, localId=${message.localId}, fileName=${message.originalFileName}, filePath=${message.localFilePath}, status=${message.status.name}, mediaType=${message.type.name}');
    
    return message;
  }

  @override
  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
