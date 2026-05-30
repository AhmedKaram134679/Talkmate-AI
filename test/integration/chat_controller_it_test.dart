import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';

import '_common_it.dart';

void main() {
  group('IT: ChatController End-to-End', () {
    late ChatController chatController;
    late AuthController authController;

    setUp(() async {
      if (!ItEnv.enabled) return;

      final ready = await ensureFirebaseInitialized();
      if (!ready) return;

      // Initialize GetX controllers
      Get.testMode = true;
      authController = Get.put(AuthController());
      chatController = Get.put(ChatController());

      // Mock user login
      final userId = 'it_user_${Random().nextInt(1 << 32)}';
      authController.setMockUser(userId, 'Test User', 'test@example.com');

      // Disable mock data to use real Firestore
      // AppConfig.useMockData is now const false by default
      AppConfig.enableFirebase = true;
    });

    tearDown(() {
      Get.reset();
    });

    test('create chat, send message, typing indicators', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureFirebaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Firebase not available');
        return;
      }

      final otherUserId = 'it_other_${Random().nextInt(1 << 32)}';

      // Create individual chat
      final chat = await chatController.createIndividualChat(
        otherUserId: otherUserId,
        otherUserName: 'Other User',
      );

      expect(chat.id, isNotEmpty);
      expect(chat.participantIds.contains(authController.userId), true);
      expect(chat.participantIds.contains(otherUserId), true);

      // Send a message
      await chatController.sendMessage(
        chatId: chat.id,
        content: 'Hello from integration test!',
      );

      // Wait for message to appear
      await Future.delayed(const Duration(seconds: 2));

      final messages = chatController.getMessagesForChat(chat.id);
      expect(messages.isNotEmpty, true);
      expect(messages.last.content, 'Hello from integration test!');

      // Test typing indicators
      await chatController.startTyping(chat.id);
      await Future.delayed(const Duration(milliseconds: 500));

      final typingUsers = chatController.getTypingUserNames(chat.id);
      // Should be empty since we're checking our own typing
      expect(typingUsers.isEmpty, true);

      await chatController.stopTyping(chat.id);

      // Mark messages as read
      await chatController.markChatMessagesRead(chat.id);

      // Clean up
      await chatController.deleteChat(chat.id);
    });

    test('group chat creation and messaging', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureFirebaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Firebase not available');
        return;
      }

      final user2 = 'it_user2_${Random().nextInt(1 << 32)}';
      final user3 = 'it_user3_${Random().nextInt(1 << 32)}';

      // Create group chat
      final groupChat = await chatController.createGroupChat(
        name: 'Test Group',
        participantIds: [user2, user3],
        description: 'Integration test group',
      );

      expect(groupChat.id, isNotEmpty);
      expect(groupChat.type.name, 'group');
      expect(groupChat.participantIds.length, 3); // current user + 2 others

      // Send message to group
      await chatController.sendMessage(
        chatId: groupChat.id,
        content: 'Hello group!',
      );

      // Wait and verify
      await Future.delayed(const Duration(seconds: 2));
      final groupMessages = chatController.getMessagesForChat(groupChat.id);
      expect(groupMessages.isNotEmpty, true);

      // Clean up
      await chatController.deleteChat(groupChat.id);
    });
  });
}
