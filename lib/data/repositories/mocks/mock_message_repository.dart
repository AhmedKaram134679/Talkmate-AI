import 'dart:async';

import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:uuid/uuid.dart';

class MockMessageRepository implements IMessageRepository {
  MockMessageRepository._();
  static final MockMessageRepository instance = MockMessageRepository._();

  final Map<String, List<Message>> _messages = {}; // chatId -> messages
  final Map<String, StreamController<List<Message>>> _controllers =
      {}; // chatId -> controller

  // 50 MB soft limit for mock media messages
  static const int maxMediaBytes = 50 * 1024 * 1024;

  StreamController<List<Message>> _controllerFor(String chatId) {
    // ignore: close_sinks
    return _controllers.putIfAbsent(
      chatId,
      () => StreamController<List<Message>>.broadcast(),
    );
  }

  void _emit(String chatId) {
    // ignore: close_sinks
    final ctrl = _controllerFor(chatId);
    final list = List<Message>.from(_messages[chatId] ?? const []);
    ctrl.add(list);
  }

  @override
  Future<Message> sendMessage({
    required String chatId,
    required String senderId,
    MessageType type = MessageType.text,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    int? mediaSize,
    String? replyToMessageId,
    String? localId,
    DateTime? createdAt,
  }) async {
    // Enforce a simple size constraint for media messages in mock
    if (type != MessageType.text &&
        mediaSize != null &&
        mediaSize > maxMediaBytes) {
      throw ArgumentError(
          'mediaSize exceeds mock limit of $maxMediaBytes bytes');
    }
    final now = createdAt ?? DateTime.now();
    final msg = Message(
      id: const Uuid().v4(),
      chatId: chatId,
      senderId: senderId,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      mediaSize: mediaSize,
      status: MessageStatus.sent,
      createdAt: now,
      localId: localId ?? const Uuid().v4(),
      replyToMessageId: replyToMessageId,
    );
    final list = _messages.putIfAbsent(chatId, () => <Message>[]);
    list.add(msg);
    _emit(chatId);
    return msg;
  }

  @override
  Stream<List<Message>> watchChatMessages(String chatId, {int limit = 100}) {
    // emit current snapshot immediately
    Future.microtask(() => _emit(chatId));
    return _controllerFor(chatId).stream;
  }

  @override
  Future<void> updateStatus(
      String chatId, String messageId, MessageStatus status) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: m.reactions,
      deletedFor: m.deletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> markChatAsRead(String chatId) async {
    final list = _messages[chatId];
    if (list == null) return;

    bool changed = false;
    for (int i = 0; i < list.length; i++) {
      final m = list[i];
      if (m.status != MessageStatus.read) {
        list[i] = Message(
          id: m.id,
          chatId: m.chatId,
          senderId: m.senderId,
          type: m.type,
          text: m.text,
          mediaUrl: m.mediaUrl,
          thumbnailUrl: m.thumbnailUrl,
          mediaSize: m.mediaSize,
          status: MessageStatus.read,
          createdAt: m.createdAt,
          editedAt: m.editedAt,
          reactions: m.reactions,
          deletedFor: m.deletedFor,
          deleted: m.deleted,
          replyToMessageId: m.replyToMessageId,
          deletedByName: m.deletedByName,
        );
        changed = true;
      }
    }

    if (changed) {
      _emit(chatId);
    }
  }

  @override
  Future<void> addReaction(
      String chatId, String messageId, String userId, String emoji) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    final newReactions = Map<String, String>.from(m.reactions ?? {});
    newReactions[userId] = emoji;

    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: newReactions,
      deletedFor: m.deletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> removeReaction(
      String chatId, String messageId, String userId, String emoji) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    if (m.reactions == null) return;
    final newReactions = Map<String, String>.from(m.reactions!);
    if (newReactions[userId] == emoji) {
      newReactions.remove(userId);
    }

    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: newReactions,
      deletedFor: m.deletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> editMessageText(
      String chatId, String messageId, String newText) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: newText,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: DateTime.now(),
      reactions: m.reactions,
      deletedFor: m.deletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
    required String userId,
  }) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    final newDeletedFor = Map<String, bool>.from(m.deletedFor ?? {});
    newDeletedFor[userId] = true;

    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: m.reactions,
      deletedFor: newDeletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> softDeleteForAll(
      {required String chatId,
      required String messageId,
      required String deletedByName}) async {
    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;
    final m = list[i];
    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: m.reactions,
      deletedFor: m.deletedFor,
      deleted: true,
      replyToMessageId: m.replyToMessageId,
      deletedByName: deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    const mockUserId = 'mock_current_user_id';

    final list = _messages[chatId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == messageId);
    if (i == -1) return;

    final m = list[i];
    final reactions = Map<String, String>.from(m.reactions ?? {});
    final existing = reactions[mockUserId];

    if (existing == emoji) {
      reactions.remove(mockUserId);
    } else {
      reactions[mockUserId] = emoji;
    }

    list[i] = Message(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      type: m.type,
      text: m.text,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      mediaSize: m.mediaSize,
      status: m.status,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      reactions: reactions,
      deletedFor: m.deletedFor,
      deleted: m.deleted,
      replyToMessageId: m.replyToMessageId,
      deletedByName: m.deletedByName,
    );
    _emit(chatId);
  }

  @override
  Future<void> close() async {
    for (final ctrl in _controllers.values) {
      await ctrl.close();
    }
    _controllers.clear();
  }
}
