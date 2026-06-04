import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/models/sync_action_model.dart';
import '../contracts/i_local_message_repository.dart';

class LocalMessageRepository implements ILocalMessageRepository {
  // In-memory storage for Web
  final Map<String, Message> _messages = {};
  final Map<String, SyncAction> _syncActions = {};

  // Reactive stream controller using BehaviorSubject for efficient updates
  final _messageController = BehaviorSubject<List<Message>>.seeded([]);

  LocalMessageRepository() {
    _emit();
  }

  void _emit() {
    _messageController.add(_messages.values.toList());
  }

  @override
  Future<List<Message>> getChatMessages(String chatId) async {
    return _messages.values.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<List<Message>> getPendingMessages() async {
    return _messages.values
        .where((m) => m.status == MessageStatus.pending)
        .toList();
  }

  @override
  Future<List<SyncAction>> getPendingSyncActions() async {
    return _syncActions.values.toList();
  }

  @override
  Future<void> saveMessage(Message message) async {
    // Upsert logic
    if (message.localId != null) {
      _messages[message.localId!] = message;
      _emit();
    }
  }

  @override
  Future<void> saveSyncAction(SyncAction action) async {
    _syncActions[action.id] = action;
  }

  @override
  Future<void> updateMessageStatus(String localId, MessageStatus status,
      {String? serverId}) async {
    if (_messages.containsKey(localId)) {
      final old = _messages[localId]!;
      _messages[localId] = old.copyWith(
        status: status,
        id: serverId ?? old.id,
      );
      _emit();
    }
  }

  @override
  Future<void> deleteMessage(String localId) async {
    _messages.remove(localId);
    _emit();
  }

  @override
  Future<void> deleteSyncAction(String actionId) async {
    _syncActions.remove(actionId);
  }

  @override
  Future<void> clearChat(String chatId) async {
    _messages.removeWhere((key, value) => value.chatId == chatId);
    _emit();
  }

  @override
  Stream<List<Message>> watchChatMessages(String chatId) {
    return _messageController.stream.map((allMessages) {
      final chatMsgs = allMessages.where((m) => m.chatId == chatId).toList();
      chatMsgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return chatMsgs;
    });
  }

  @override
  Future<void> close() async {
    await _messageController.close();
  }
}
