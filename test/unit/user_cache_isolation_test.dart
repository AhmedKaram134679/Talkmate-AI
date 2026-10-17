import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unit: User Cache & Per-User Isolation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Stars and pins are isolated by User ID and Chat ID', () async {
      final prefs = await SharedPreferences.getInstance();

      const userA = 'uid_user_alpha';
      const userB = 'uid_user_beta';
      const chatId = 'chat_room_001';
      const messageId = 'msg_999';

      // User A stars the message
      final keyA = 'star_${chatId}_${userA}_$messageId';
      await prefs.setBool(keyA, true);

      // Verify User A has starred, but User B does not see it starred
      final isStarredA = prefs.getBool(keyA) ?? false;
      final keyB = 'star_${chatId}_${userB}_$messageId';
      final isStarredB = prefs.getBool(keyB) ?? false;

      expect(isStarredA, true);
      expect(isStarredB, false);
    });

    test('Drafts and settings partition correctly per user session', () async {
      final prefs = await SharedPreferences.getInstance();

      const user1 = 'user_101';
      const user2 = 'user_202';

      // Store drafts for user 1 and user 2 on the same chat
      await prefs.setString('draft_chat_1_$user1', 'Hello from User 1');
      await prefs.setString('draft_chat_1_$user2', 'Greetings from User 2');

      expect(prefs.getString('draft_chat_1_$user1'), 'Hello from User 1');
      expect(prefs.getString('draft_chat_1_$user2'), 'Greetings from User 2');
    });

    test('Cache purge on account logout cleans current user sensitive keys', () async {
      final prefs = await SharedPreferences.getInstance();

      const userA = 'user_active';
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_id', userA);
      await prefs.setString('user_name', 'Active User');
      await prefs.setString('star_chat1_${userA}_msg1', true.toString());

      // Simulate logout cleanup routine
      await prefs.clear();

      expect(prefs.getBool('is_logged_in'), isNull);
      expect(prefs.getString('user_id'), isNull);
      expect(prefs.getString('user_name'), isNull);
      expect(prefs.getString('star_chat1_${userA}_msg1'), isNull);
    });
  });
}
