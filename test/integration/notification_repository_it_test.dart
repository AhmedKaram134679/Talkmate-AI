import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/notification_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_notification_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: NotificationRepository (Supabase)', () {
    test('send/watch/markAsRead', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseNotificationRepository();
      Get.put<INotificationRepository>(repo);

      final uid = 'it_u_${Random().nextInt(1 << 32)}';

      await repo.sendNotification(
        toUserId: uid,
        type: NotificationType.message.name,
        title: 'IT msg',
        body: 'hello notif',
        data: {'k': 'v'},
      );

      final list = await repo.watchUserNotifications(uid).first;
      expect(list.isNotEmpty, true);
      final first = list.first;
      expect(first.title, 'IT msg');

      await repo.markAsRead(uid, first.id);
      final updatedList = await repo.watchUserNotifications(uid).first;
      final updated = updatedList.firstWhere((n) => n.id == first.id);
      expect(updated.read, true);
    });
  });
}
