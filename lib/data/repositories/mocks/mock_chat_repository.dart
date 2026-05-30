import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:talkmate_ai/data/models/chat_model.dart';
import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';

class MockChatRepository implements IChatRepository {
  MockChatRepository._();
  static final MockChatRepository instance = MockChatRepository._();

  final Map<String, Chat> _chats = {}; // chatId -> Chat
  final Map<String, StreamController<Chat?>> _chatCtrls = {}; // chatId -> ctrl
  final Map<String, StreamController<List<Chat>>> _userCtrls =
      {}; // userId -> ctrl

  StreamController<Chat?> _chatCtrl(String id) =>
      _chatCtrls.putIfAbsent(id, () => StreamController<Chat?>.broadcast());
  StreamController<List<Chat>> _userCtrl(String id) => _userCtrls.putIfAbsent(
        id,
        () => StreamController<List<Chat>>.broadcast(),
      );

  void _emitChat(String id) => _chatCtrl(id).add(_chats[id]);

  void _emitUser(String userId) {
    final list = _chats.values
        .where((c) => c.participantIds.contains(userId))
        .toList()
      ..sort((a, b) => (b.lastMessageAt ?? b.createdAt)
          .compareTo(a.lastMessageAt ?? a.createdAt));
    _userCtrl(userId).add(list);
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Future<Chat> createChat({
    required List<String> participantIds,
    bool isGroup = false,
    String? groupName,
    String? groupPhotoUrl,
  }) async {
    final id = _genId();
    final chat = Chat(
      id: id,
      participantIds: participantIds,
      isGroup: isGroup,
      groupName: groupName,
      groupPhotoUrl: groupPhotoUrl,
      createdAt: DateTime.now(),
      updatedAt: null,
      lastMessageText: null,
      lastMessageSenderId: null,
      lastMessageAt: null,
    );
    _chats[id] = chat;
    for (final u in participantIds) {
      _emitUser(u);
    }
    _emitChat(id);
    return chat;
  }

  @override
  Future<Chat?> getById(String chatId) async => _chats[chatId];

  @override
  Stream<Chat?> watchById(String chatId) {
    Future.microtask(() => _emitChat(chatId));
    return _chatCtrl(chatId).stream;
  }

  @override
  Stream<List<Chat>> watchUserChats(String userId) {
    Future.microtask(() => _emitUser(userId));
    return _userCtrl(userId).stream;
  }

  @override
  Stream<List<Chat>> watchUserChatsNoOrder(String userId) {
    // Same as ordered in mock; real impl may differ
    return watchUserChats(userId);
  }

  @override
  Future<void> updateLastMessage({
    required String chatId,
    required Message message,
  }) async {
    final c = _chats[chatId];
    if (c == null) return;
    final updated = Chat(
      id: c.id,
      participantIds: c.participantIds,
      isGroup: c.isGroup,
      groupName: c.groupName,
      groupPhotoUrl: c.groupPhotoUrl,
      createdAt: c.createdAt,
      updatedAt: DateTime.now(),
      lastMessageText: message.text,
      lastMessageSenderId: message.senderId,
      lastMessageAt: message.createdAt,
    );
    _chats[chatId] = updated;
    for (final u in c.participantIds) {
      _emitUser(u);
    }
    _emitChat(chatId);
  }

  @override
  Future<void> removeUserFromChat({
    required String chatId,
    required String userId,
  }) async {
    final c = _chats[chatId];
    if (c == null) return;
    final updated = Chat(
      id: c.id,
      participantIds: c.participantIds.where((e) => e != userId).toList(),
      isGroup: c.isGroup,
      groupName: c.groupName,
      groupPhotoUrl: c.groupPhotoUrl,
      createdAt: c.createdAt,
      updatedAt: DateTime.now(),
      lastMessageText: c.lastMessageText,
      lastMessageSenderId: c.lastMessageSenderId,
      lastMessageAt: c.lastMessageAt,
    );
    _chats[chatId] = updated;
    for (final u in c.participantIds) {
      _emitUser(u);
    }
    _emitChat(chatId);
  }

  // Mock-specific helper to update group metadata
  @override
  Future<void> updateGroupMeta({
    required String chatId,
    String? name,
    String? description,
    String? photoUrl,
  }) async {
    final c = _chats[chatId];
    if (c == null) return;
    if (!c.isGroup) return; // no-op for non-group chats
    final updated = Chat(
      id: c.id,
      participantIds: c.participantIds,
      isGroup: c.isGroup,
      groupName: name ?? c.groupName,
      groupPhotoUrl: photoUrl ?? c.groupPhotoUrl,
      createdAt: c.createdAt,
      updatedAt: DateTime.now(),
      lastMessageText: c.lastMessageText,
      lastMessageSenderId: c.lastMessageSenderId,
      lastMessageAt: c.lastMessageAt,
    );
    _chats[chatId] = updated;
    for (final u in c.participantIds) {
      _emitUser(u);
    }
    _emitChat(chatId);
  }

  @override
  Future<void> updateParticipantSettings({
    required String chatId,
    required String userId,
    bool? isPinned,
    bool? isMuted,
    DateTime? muteUntil,
    bool? isArchived,
  }) async {
    // In mock, we don't have a separate table, so we might need a Map<userId, Settings> if we cared
    // but for now, no-op or partial log is fine
    debugPrint(
        'Mock updateParticipantSettings: $chatId, $userId, muteUntil: $muteUntil');
  }

  @override
  Future<void> addUsersToChat({
    required String chatId,
    required List<String> userIds,
  }) async {
    final c = _chats[chatId];
    if (c == null) return;
    final newParticipants = [...c.participantIds];
    for (final uid in userIds) {
      if (!newParticipants.contains(uid)) {
        newParticipants.add(uid);
      }
    }
    final updated = Chat(
      id: c.id,
      participantIds: newParticipants,
      isGroup: c.isGroup,
      groupName: c.groupName,
      groupPhotoUrl: c.groupPhotoUrl,
      createdAt: c.createdAt,
      updatedAt: DateTime.now(),
      lastMessageText: c.lastMessageText,
      lastMessageSenderId: c.lastMessageSenderId,
      lastMessageAt: c.lastMessageAt,
    );
    _chats[chatId] = updated;
    for (final u in newParticipants) {
      _emitUser(u);
    }
    _emitChat(chatId);
  }

  @override
  Future<void> close() async {
    for (final ctrl in _chatCtrls.values) {
      await ctrl.close();
    }
    _chatCtrls.clear();
    for (final ctrl in _userCtrls.values) {
      await ctrl.close();
    }
    _userCtrls.clear();
  }
}
