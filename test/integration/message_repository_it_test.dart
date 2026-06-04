import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_message_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: MessageRepository (Supabase)', () {
    test('send/watch/updateStatus', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final chats = SupabaseChatRepository();
      final repo = SupabaseMessageRepository();
      Get.put<IChatRepository>(chats);
      Get.put<IMessageRepository>(repo);

      final u1 = 'it_u_${Random().nextInt(1 << 32)}';
      final u2 = 'it_u_${Random().nextInt(1 << 32)}';
      final chat = await chats.createChat(participantIds: [u1, u2]);

      final sent = await repo.sendMessage(
        chatId: chat.id,
        senderId: u1,
        type: MessageType.text,
        text: 'hello msg IT',
      );
      expect(sent.id, isNotEmpty);

      final list = await repo.watchChatMessages(chat.id).first;
      expect(list.any((m) => m.id == sent.id), true);

      await repo.updateStatus(chat.id, sent.id, MessageStatus.read);
      final updatedList = await repo.watchChatMessages(chat.id).first;
      final updated = updatedList.firstWhere((m) => m.id == sent.id);
      expect(updated.status, MessageStatus.read);
    });
  });
}
