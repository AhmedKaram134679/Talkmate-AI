import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_notification_repository.dart';

void main() {
  group('MockNotificationRepository', () {
    final repo = MockNotificationRepository.instance;

    test('sendNotification appears in stream and markAsRead updates state',
        () async {
      await repo.sendNotification(
        toUserId: 'u1',
        type: 'message',
        title: 'New Message',
        body: 'Hello',
      );
      final firstList = await repo.watchUserNotifications('u1').first;
      expect(firstList.isNotEmpty, true);
      final notif = firstList.first;

      await repo.markAsRead('u1', notif.id);
      final updatedList = await repo.watchUserNotifications('u1').first;
      final updated = updatedList.firstWhere((n) => n.id == notif.id);
      expect(updated.read, true);
    });

    test('multiple types mapping and data payload', () async {
      await repo.sendNotification(
        toUserId: 'u2',
        type: 'friendRequest',
        title: 'FR',
        body: 'From u9',
        data: {'from': 'u9'},
      );
      await repo.sendNotification(
        toUserId: 'u2',
        type: 'groupInvite',
        title: 'Invite',
        body: 'Join g1',
        data: {'groupId': 'g1'},
      );
      await repo.sendNotification(
        toUserId: 'u2',
        type: 'call',
        title: 'Incoming Call',
        body: 'u3 is calling',
        data: {'callId': 'c123'},
      );

      final list = await repo.watchUserNotifications('u2').first;
      expect(list.length >= 3, true);
      expect(list.any((n) => n.type.name == 'friendRequest'), true);
      expect(list.any((n) => n.type.name == 'groupInvite'), true);
      expect(list.any((n) => n.type.name == 'call'), true);
      final callNotif = list.firstWhere((n) => n.type.name == 'call');
      expect(callNotif.data?['callId'], 'c123');
    });
  });
}
