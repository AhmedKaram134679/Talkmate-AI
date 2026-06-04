import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_user_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: UserRepository (Supabase)', () {
    test('upsert/getById/watch/search', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      // Initialize repository
      final repo = SupabaseUserRepository();
      Get.put<IUserRepository>(repo);

      final id = 'it_user_${Random().nextInt(1 << 32)}';
      final user = AppUser(
        id: id,
        email: '$id@example.com',
        displayName: 'It Tester',
        createdAt: DateTime.now(),
        status: UserStatus.online,
      );

      await repo.upsertUser(user);

      final fetched = await repo.getById(id);
      expect(fetched?.email, user.email);

      final watched = await repo.watchById(id).first;
      expect(watched?.id, id);

      final results = await repo.searchByNameOrEmail('It Tes');
      expect(results.any((u) => u.id == id), true);
    });
  });
}
