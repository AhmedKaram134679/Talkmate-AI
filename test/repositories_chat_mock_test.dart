import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_chat_repository.dart';

void main() {
  group('MockChatRepository', () {
    final repo = MockChatRepository.instance;

    test('createChat and watchUserChats', () async {
      final c = await repo.createChat(participantIds: const ['u1', 'u2']);
      expect(c.id, isNotEmpty);

      final userChats = await repo.watchUserChats('u1').first;
      expect(userChats.where((e) => e.id == c.id).isNotEmpty, true);
    });

    test('updateLastMessage updates metadata', () async {
      final c = await repo.createChat(participantIds: const ['u1', 'u3']);
      final msg = Message(
        id: 'm1',
        chatId: c.id,
        senderId: 'u1',
        type: MessageType.text,
        text: 'hello',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      );
      await repo.updateLastMessage(chatId: c.id, message: msg);
      final updated = await repo.watchById(c.id).first;
      expect(updated?.lastMessageText, 'hello');
      expect(updated?.lastMessageSenderId, 'u1');
    });

    test('removeUserFromChat removes participant', () async {
      final c = await repo.createChat(participantIds: const ['u1', 'u4']);
      await repo.removeUserFromChat(chatId: c.id, userId: 'u4');
      final updated = await repo.getById(c.id);
      expect(updated!.participantIds.contains('u4'), false);
    });

    test('updateGroupMeta updates groupName and groupPhotoUrl', () async {
      final c = await repo.createChat(
        participantIds: const ['g1', 'g2', 'g3'],
        isGroup: true,
        groupName: 'Old Name',
        groupPhotoUrl: 'old.png',
      );

      await repo.updateGroupMeta(
        chatId: c.id,
        name: 'New Name',
        photoUrl: 'new.png',
      );

      final updated = await repo.getById(c.id);
      expect(updated?.groupName, 'New Name');
      expect(updated?.groupPhotoUrl, 'new.png');
    });
  });
}
