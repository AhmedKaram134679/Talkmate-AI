import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_friendship_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: FriendshipRepository (Supabase)', () {
    test('create/areFriends/getAllForUser/watchAllForUser', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseFriendshipRepository();
      Get.put<IFriendshipRepository>(repo);

      final userX = 'it_friend_x_${Random().nextInt(1 << 32)}';
      final userY = 'it_friend_y_${Random().nextInt(1 << 32)}';

      // Initially not friends
      expect(await repo.areFriends(userX, userY), false);

      // Create friendship
      await repo.createFriendship(userA: userX, userB: userY);

      // Now they are friends
      expect(await repo.areFriends(userX, userY), true);
      expect(await repo.areFriends(userY, userX), true); // symmetric

      // Get all friendships for userX
      final allX = await repo.getAllForUser(userX);
      expect(allX, contains(userY));

      // Watch friendships for userY
      final watchedY = await repo.watchAllForUser(userY).first;
      expect(watchedY, contains(userX));

      // Try creating duplicate (should return existing)
      await repo.createFriendship(userA: userY, userB: userX);
      expect(await repo.areFriends(userX, userY), true);
    });

    test('watchAllForUser emits list containing friendship', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseFriendshipRepository();
      Get.put<IFriendshipRepository>(repo);

      await repo.createFriendship(userA: 'x', userB: 'y');
      final stream = repo.watchAllForUser('x');
      final initial = await stream.first;
      expect(initial, contains('y'));
    });
  });
}
