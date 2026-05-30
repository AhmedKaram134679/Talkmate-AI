import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_typing_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_typing_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: TypingRepository (Supabase)', () {
    test('start/update/stop/watch typing indicators', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseTypingRepository();
      Get.put<ITypingRepository>(repo);

      final chatId = 'it_chat_${Random().nextInt(1 << 32)}';
      final userId = 'it_user_${Random().nextInt(1 << 32)}';

      // Start typing
      await repo.startTyping(chatId, userId);

      // Watch typing indicators
      final indicators = await repo.watchTyping(chatId).first;
      expect(indicators.any((i) => i.userId == userId), true);

      // Update typing
      await repo.updateTyping(chatId, userId);

      // Stop typing
      await repo.stopTyping(chatId, userId);

      // Verify typing stopped
      await Future.delayed(const Duration(milliseconds: 500));
      final afterStop = await repo.watchTyping(chatId).first;
      expect(afterStop.any((i) => i.userId == userId), false);
    });
  });
}
