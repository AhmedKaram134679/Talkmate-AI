import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_message_repository.dart';

void main() {
  group('MockMessageRepository', () {
    final repo = MockMessageRepository.instance;
    const chatId = 'c1';
    const senderId = 'u1';

    test('sendMessage returns created message', () async {
      final m = await repo.sendMessage(chatId: chatId, senderId: senderId, text: 'hi');
      expect(m.id, isNotEmpty);
      expect(m.chatId, chatId);
      expect(m.senderId, senderId);
      expect(m.type, MessageType.text);
      expect(m.text, 'hi');
      expect(m.status, MessageStatus.sent);
    });

    test('watchChatMessages emits on send and updateStatus', () async {
      final messages = <List<Message>>[];
      final sub = repo.watchChatMessages(chatId).listen(messages.add);
      addTearDown(sub.cancel);

      final m1 = await repo.sendMessage(chatId: chatId, senderId: senderId, text: 'hello');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(messages.isNotEmpty, true);
      expect(messages.last.any((e) => e.id == m1.id), true);

      await repo.updateStatus(chatId, m1.id, MessageStatus.read);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final updated = messages.last.firstWhere((e) => e.id == m1.id);
      expect(updated.status, MessageStatus.read);
    });

    test('sendMessage image within size limit succeeds', () async {
      // 1 MB image
      final m = await repo.sendMessage(
        chatId: chatId,
        senderId: senderId,
        type: MessageType.image,
        mediaUrl: 'http://example.com/img.jpg',
        mediaSize: 1 * 1024 * 1024,
      );
      expect(m.type, MessageType.image);
      expect(m.mediaUrl, isNotEmpty);
      expect(m.mediaSize, 1 * 1024 * 1024);
    });

    test('sendMessage media exceeding size limit throws', () async {
      // 60 MB should exceed the mock limit (50 MB)
      expect(
        () => repo.sendMessage(
          chatId: chatId,
          senderId: senderId,
          type: MessageType.video,
          mediaUrl: 'http://example.com/video.mp4',
          mediaSize: 60 * 1024 * 1024,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
