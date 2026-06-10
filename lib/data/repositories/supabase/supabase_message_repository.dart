import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';
import 'package:uuid/uuid.dart';

class SupabaseMessageRepository implements IMessageRepository {
  SupabaseMessageRepository();

  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<Message> sendMessage({
    required String chatId,
    required String senderId,
    MessageType type = MessageType.text,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? mediaSize,
    String? replyToMessageId,
    String? localId,
    DateTime? createdAt,
  }) async {
    final messageId = localId ?? const Uuid().v4();
    final now = createdAt ?? DateTime.now();

    final messageData = {
      'id': messageId,
      'local_id': messageId, // Store client ID as local_id for sync tracking
      'chat_id': chatId,
      'sender_id': senderId,
      'type': type.name,
      'text': text,
      'media_url': mediaUrl,
      'thumbnail_url': thumbnailUrl,
      'media_size': mediaSize,
      'reply_to_message_id': replyToMessageId,
      'status': MessageStatus.sent.name,
      'created_at': now.toIso8601String(),
    };

    // Log MESSAGE_SYNC_STARTED
    ForensicLogger.log(
      tag: 'MESSAGE_SYNC_STARTED',
      messageId: messageId,
      chatId: chatId,
      fileName: text,
      status: 'sending',
    );

    try {
      final response = await _client
          .from('messages')
          .upsert(messageData)
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      final syncedMessage = Message.fromJson(response, response['id']);

      // Log MESSAGE_SYNC_SUCCESS
      ForensicLogger.log(
        tag: 'MESSAGE_SYNC_SUCCESS',
        messageId: messageId,
        chatId: chatId,
        status: 'sent',
      );

      return syncedMessage;
    } catch (e) {
      debugPrint('SupabaseMessageRepository: sendMessage error: $e');

      // Log MESSAGE_SYNC_FAILED
      ForensicLogger.log(
        tag: 'MESSAGE_SYNC_FAILED',
        messageId: messageId,
        chatId: chatId,
        status: 'failed',
        extra: 'error=$e',
      );

      rethrow;
    }
  }

  @override
  Stream<List<Message>> watchChatMessages(String chatId, {int limit = 100}) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((data) =>
            data.map((map) => Message.fromJson(map, map['id'])).toList());
  }

  @override
  Future<void> updateStatus(
      String chatId, String messageId, MessageStatus status) async {
    try {
      await _client.rpc('fn_update_message_status', params: {
        'p_message_id': messageId,
        'p_status': status.name,
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('SupabaseMessageRepository: updateStatus error: $e');
      // No rethrow here to prevent downstream crashing for background status updates
    }
  }

  @override
  Future<void> markChatAsRead(String chatId) async {
    await _client.rpc('fn_mark_chat_as_read', params: {
      'p_chat_id': chatId,
    });
  }

  @override
  Future<void> addReaction(
      String chatId, String messageId, String userId, String emoji) async {
    await _client.rpc('fn_toggle_reaction_v4', params: {
      'p_message_id': messageId,
      'p_chat_id': chatId,
      'p_emoji': emoji,
    });
  }

  @override
  Future<void> removeReaction(
      String chatId, String messageId, String userId, String emoji) async {
    // Stage R: In V4, fn_toggle_reaction_v4 handles removal if the same emoji is passed.
    await _client.rpc('fn_toggle_reaction_v4', params: {
      'p_message_id': messageId,
      'p_chat_id': chatId,
      'p_emoji': emoji,
    });
  }

  @override
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    await _client.rpc('fn_toggle_reaction_v4', params: {
      'p_message_id': messageId,
      'p_chat_id': chatId,
      'p_emoji': emoji,
    });
  }

  @override
  Future<void> editMessageText(
      String chatId, String messageId, String newText) async {
    await _client.from('messages').update({
      'text': newText,
      'is_edited': true,
      'edited_at': DateTime.now().toIso8601String(),
    }).eq('id', messageId);
  }

  @override
  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
    required String userId,
  }) async {
    try {
      // 1. Fetch current 'deleted_for' map
      final res = await _client
          .from('messages')
          .select('deleted_for')
          .eq('id', messageId)
          .single();

      final currentMap = res['deleted_for'] != null
          ? Map<String, dynamic>.from(res['deleted_for'])
          : <String, dynamic>{};

      // 2. Add current user
      currentMap[userId] = true;

      // 3. Update column
      await _client
          .from('messages')
          .update({'deleted_for': currentMap}).eq('id', messageId);
    } catch (e) {
      // Fallback or rethrow - assuming RPC might exist but failed,
      // but here we completely replaced RPC.
      // If the RPC existed and did other things (like hiding), we might miss it,
      // but 'deleted_for' is the standard pattern.
      rethrow;
    }
  }

  @override
  Future<void> softDeleteForAll({
    required String chatId,
    required String messageId,
    required String deletedByName,
  }) async {
    await _client.from('messages').update({
      'is_deleted': true,
      'deleted_by_name': deletedByName,
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', messageId);
  }

  @override
  Future<void> close() async {}
}
