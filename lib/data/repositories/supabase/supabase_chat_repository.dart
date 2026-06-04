import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/chat_model.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';

class SupabaseChatRepository implements IChatRepository {
  SupabaseChatRepository();

  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<Chat> createChat({
    required List<String> participantIds,
    bool isGroup = false,
    String? groupName,
    String? groupPhotoUrl,
  }) async {
    try {
      final response = await _client
          .from('conversations')
          .insert({
            'is_group': isGroup,
            'group_name': groupName,
            'group_photo_url': groupPhotoUrl,
            'creator_id': _client.auth.currentUser!.id,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      final chatId = response['id'];
      final participantsData = participantIds
          .map((uid) => {
                'conversation_id': chatId,
                'user_id': uid,
              })
          .toList();

      await _client
          .from('conversation_participants')
          .insert(participantsData)
          .timeout(const Duration(seconds: 10));

      return Chat.fromJson(response, response['id']);
    } catch (e) {
      debugPrint('SupabaseChatRepository: createChat error: $e');
      rethrow;
    }
  }

  @override
  Future<Chat?> getById(String chatId) async {
    final response = await _client
        .from('conversations')
        .select()
        .eq('id', chatId)
        .maybeSingle();
    if (response == null) return null;
    return Chat.fromJson(response, response['id']);
  }

  @override
  Stream<Chat?> watchById(String chatId) {
    // Stream conversation metadata
    final conversationStream = _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('id', chatId)
        .map((data) => data.isNotEmpty ? data.first : null);

    // Stream participants to get IDs and current user settings
    final participantsStream = _client
        .from('conversation_participants')
        .stream(primaryKey: ['conversation_id', 'user_id']).eq(
            'conversation_id', chatId);

    return Rx.combineLatest2<Map<String, dynamic>?, List<Map<String, dynamic>>,
        Chat?>(
      conversationStream,
      participantsStream,
      (convData, participantsData) {
        if (convData == null) return null;

        // Extract all participant IDs
        final pIds =
            participantsData.map((r) => r['user_id'] as String).toList();

        // Find current user's settings (mute, pin, etc.)
        final currentUserId = _client.auth.currentUser?.id;
        final myParticipantRow = participantsData.firstWhere(
          (r) => r['user_id'] == currentUserId,
          orElse: () => {},
        );

        // Merge data for Chat.fromJson
        final mergedData = Map<String, dynamic>.from(convData);
        mergedData['participant_ids'] = pIds;

        if (myParticipantRow.isNotEmpty) {
          mergedData['is_pinned'] = myParticipantRow['is_pinned'];
          mergedData['is_muted'] = myParticipantRow['is_muted'];
          mergedData['mute_until'] = myParticipantRow['mute_until'];
          mergedData['is_archived'] = myParticipantRow['is_archived'];
        }

        return Chat.fromJson(mergedData, chatId);
      },
    );
  }

  @override
  Stream<List<Chat>> watchUserChats(String userId) {
    return _client
        .from('conversation_participants')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', userId)
        .asyncMap((participantRecords) async {
          if (participantRecords.isEmpty) return [];

          final chatIds =
              participantRecords.map((r) => r['conversation_id']).toList();

          final chatsResponse = await _client
              .from('conversations')
              .select()
              .filter('id', 'in', chatIds)
              .order('last_message_time', ascending: false);

          // Fetch participants for these chats to populate participantIds and user settings
          final allParticipants = await _client
              .from('conversation_participants')
              .select(
                  'conversation_id, user_id, is_pinned, is_muted, mute_until, is_archived')
              .filter('conversation_id', 'in', chatIds);

          final participantsMap = <String, List<String>>{};
          final userSettingsMap = <String, Map<String, dynamic>>{};
          final currentUserId = userId;

          for (final p in (allParticipants as List)) {
            final participantMap = p as Map<String, dynamic>;
            final cid = participantMap['conversation_id'] as String;
            final uid = participantMap['user_id'] as String;
            participantsMap.putIfAbsent(cid, () => []).add(uid);

            if (uid == currentUserId) {
              userSettingsMap[cid] = {
                'is_pinned': participantMap['is_pinned'],
                'is_muted': participantMap['is_muted'],
                'mute_until': participantMap['mute_until'],
                'is_archived': participantMap['is_archived'],
              };
            }
          }

          return chatsResponse.map((map) {
            final cid = map['id'] as String;
            final pIds = participantsMap[cid] ?? [];
            final settings = userSettingsMap[cid] ?? {};

            return Chat.fromJson(
              {...map, 'participant_ids': pIds, ...settings},
              cid,
            );
          }).toList();
        });
  }

  @override
  Stream<List<Chat>> watchUserChatsNoOrder(String userId) {
    return watchUserChats(userId);
  }

  @override
  Future<void> updateLastMessage(
      {required String chatId, required Message message}) async {
    await _client.from('conversations').update({
      'last_message_text': message.text ??
          (message.type == MessageType.image ? '📷 صورة' : '📎 ملف'),
      'last_message_time': message.createdAt.toIso8601String(),
      'last_message_sender_id': message.senderId,
    }).eq('id', chatId);
  }

  @override
  Future<void> removeUserFromChat({
    required String chatId,
    required String userId,
  }) async {
    await _client
        .from('conversation_participants')
        .delete()
        .eq('conversation_id', chatId)
        .eq('user_id', userId);
  }

  @override
  Future<void> updateParticipantSettings({
    required String chatId,
    required String userId,
    bool? isPinned,
    bool? isMuted,
    DateTime? muteUntil,
    bool? isArchived,
  }) async {
    final updates = <String, dynamic>{};
    if (isPinned != null) updates['is_pinned'] = isPinned;
    if (isMuted != null) updates['is_muted'] = isMuted;
    if (muteUntil != null) {
      updates['mute_until'] = muteUntil.toIso8601String();
    } else if (isMuted == false) {
      // If we are unmuting, clear the mute_until as well
      updates['mute_until'] = null;
    }
    if (isArchived != null) updates['is_archived'] = isArchived;

    if (updates.isNotEmpty) {
      await _client
          .from('conversation_participants')
          .update(updates)
          .eq('conversation_id', chatId)
          .eq('user_id', userId);
    }
  }

  @override
  Future<void> updateGroupMeta({
    required String chatId,
    String? name,
    String? description,
    String? photoUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['group_name'] = name;
    if (description != null) updates['group_description'] = description;
    if (photoUrl != null) updates['group_photo_url'] = photoUrl;

    if (updates.isNotEmpty) {
      await _client.from('conversations').update(updates).eq('id', chatId);
    }
  }

  @override
  Future<void> addUsersToChat({
    required String chatId,
    required List<String> userIds,
  }) async {
    final participantsData = userIds
        .map((uid) => {
              'conversation_id': chatId,
              'user_id': uid,
            })
        .toList();

    await _client.from('conversation_participants').insert(participantsData);
  }

  @override
  Future<void> close() async {}
}
