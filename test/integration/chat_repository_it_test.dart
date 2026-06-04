import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_chat_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: ChatRepository (Supabase)', () {
    test('create/get/watch/updateLastMessage/removeUser', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseChatRepository();
      Get.put<IChatRepository>(repo);

      final u1 = 'it_u_${Random().nextInt(1 << 32)}';
      final u2 = 'it_u_${Random().nextInt(1 << 32)}';

      final chat = await repo.createChat(participantIds: [u1, u2]);
      expect(chat.id, isNotEmpty);

      final fetched = await repo.getById(chat.id);
      expect(fetched?.id, chat.id);

      final list = await repo.watchUserChatsNoOrder(u1).first;
      expect(list.any((c) => c.id == chat.id), true);

      // Update last message metadata
      final msg = Message(
        id: 'tmp',
        chatId: chat.id,
        senderId: u1,
        type: MessageType.text,
        text: 'hello from IT',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );
      await repo.updateLastMessage(chatId: chat.id, message: msg);
      final updated = await repo.getById(chat.id);
      expect(updated?.lastMessageText, 'hello from IT');

      // Remove u2 from chat
      await repo.removeUserFromChat(chatId: chat.id, userId: u2);
      final afterRemoval = await repo.getById(chat.id);
      expect(afterRemoval?.participantIds.contains(u2), false);
    });
  });
}
