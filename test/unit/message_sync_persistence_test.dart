import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/models/sync_action_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_local_message_repository.dart';

class MockLocalMessageRepository implements ILocalMessageRepository {
  final Map<String, List<Message>> _store = {};
  final List<SyncAction> _syncActions = [];

  @override
  Future<void> saveMessage(Message message) async {
    final list = _store.putIfAbsent(message.chatId, () => []);
    final idx = list.indexWhere((m) =>
        m.id == message.id ||
        (m.localId != null && message.localId != null && m.localId == message.localId));
    if (idx != -1) {
      list[idx] = message;
    } else {
      list.insert(0, message);
    }
  }

  @override
  Future<List<Message>> getChatMessages(String chatId) async {
    return List.from(_store[chatId] ?? []);
  }

  @override
  Stream<List<Message>> watchChatMessages(String chatId) {
    return Stream.value(List.from(_store[chatId] ?? []));
  }

  @override
  Future<List<Message>> getPendingMessages() async {
    final all = <Message>[];
    for (var list in _store.values) {
      all.addAll(list.where(
          (m) => m.status == MessageStatus.pending || m.status == MessageStatus.failed));
    }
    return all;
  }

  @override
  Future<void> updateMessageStatus(String localId, MessageStatus status,
      {String? serverId}) async {
    for (var list in _store.values) {
      final idx = list.indexWhere((m) => m.localId == localId || m.id == localId);
      if (idx != -1) {
        final existing = list[idx];
        list[idx] = existing.copyWith(
          status: status,
          id: serverId ?? existing.id,
        );
        break;
      }
    }
  }

  @override
  Future<void> deleteMessage(String localId) async {
    for (var list in _store.values) {
      list.removeWhere((m) => m.id == localId || m.localId == localId);
    }
  }

  @override
  Future<void> clearChat(String chatId) async {
    _store.remove(chatId);
  }

  @override
  Future<void> saveSyncAction(SyncAction action) async {
    _syncActions.add(action);
  }

  @override
  Future<List<SyncAction>> getPendingSyncActions() async {
    return List.from(_syncActions);
  }

  @override
  Future<void> deleteSyncAction(String actionId) async {
    _syncActions.removeWhere((a) => a.id == actionId);
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('Unit: Message Synchronization & Local Persistence', () {
    late MockLocalMessageRepository repo;

    setUp(() {
      repo = MockLocalMessageRepository();
    });

    test('Local message creation and retrieval', () async {
      const chatId = 'chat_pers_1';
      final msg = Message(
        id: 'msg_local_1',
        localId: 'msg_local_1',
        chatId: chatId,
        senderId: 'user_sender',
        type: MessageType.text,
        text: 'Offline first message',
        createdAt: DateTime.now(),
        status: MessageStatus.pending,
      );

      await repo.saveMessage(msg);
      final messages = await repo.getChatMessages(chatId);

      expect(messages.length, 1);
      expect(messages.first.id, 'msg_local_1');
      expect(messages.first.status, MessageStatus.pending);
    });

    test('Message reconciliation from local optimistic ID to server ID', () async {
      const chatId = 'chat_pers_2';
      final optimisticMsg = Message(
        id: 'temp_opt_1',
        localId: 'temp_opt_1',
        chatId: chatId,
        senderId: 'user_sender',
        type: MessageType.text,
        text: 'Syncing message',
        createdAt: DateTime.now(),
        status: MessageStatus.pending,
      );

      await repo.saveMessage(optimisticMsg);
      expect((await repo.getPendingMessages()).length, 1);

      // Reconcile server ID on response
      const serverId = 'srv_msg_guid_999';
      await repo.updateMessageStatus('temp_opt_1', MessageStatus.sent, serverId: serverId);

      final messages = await repo.getChatMessages(chatId);
      expect(messages.first.id, serverId);
      expect(messages.first.status, MessageStatus.sent);
      expect((await repo.getPendingMessages()).isEmpty, true);
    });

    test('Clear chat messages removes only targeted conversation records', () async {
      await repo.saveMessage(Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'u1',
        type: MessageType.text,
        text: 'hello c1',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      ));
      await repo.saveMessage(Message(
        id: 'm2',
        chatId: 'c2',
        senderId: 'u1',
        type: MessageType.text,
        text: 'hello c2',
        createdAt: DateTime.now(),
        status: MessageStatus.sent,
      ));

      await repo.clearChat('c1');

      expect((await repo.getChatMessages('c1')).isEmpty, true);
      expect((await repo.getChatMessages('c2')).length, 1);
    });

    test('Offline sync action lifecycle queues and executes cleanly', () async {
      final action = SyncAction(
        id: 'sync_1',
        type: SyncActionType.markRead,
        chatId: 'c1',
        payload: {'message_id': 'm1'},
        createdAt: DateTime.now(),
      );

      await repo.saveSyncAction(action);
      final pending = await repo.getPendingSyncActions();
      expect(pending.length, 1);
      expect(pending.first.id, 'sync_1');

      await repo.deleteSyncAction('sync_1');
      expect((await repo.getPendingSyncActions()).isEmpty, true);
    });
  });
}
