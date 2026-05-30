import 'package:talkmate_ai/data/models/message_model.dart';
import 'package:talkmate_ai/data/models/sync_action_model.dart';

/// Interface for local message persistence and offline queuing
abstract class ILocalMessageRepository {
  /// Save a message locally (used for caching or pending messages)
  Future<void> saveMessage(Message message);

  /// Get all messages for a specific chat from local storage
  Future<List<Message>> getChatMessages(String chatId);

  /// Watch local messages for a specific chat
  Stream<List<Message>> watchChatMessages(String chatId);

  /// Get all messages marked as 'pending' across all chats
  Future<List<Message>> getPendingMessages();

  /// Update the status of a locally stored message
  Future<void> updateMessageStatus(String localId, MessageStatus status,
      {String? serverId});

  /// Remove a message from local storage
  Future<void> deleteMessage(String localId);

  /// Clear all cached messages for a chat
  Future<void> clearChat(String chatId);

  // Stage U: Sync Actions
  Future<void> saveSyncAction(SyncAction action);
  Future<List<SyncAction>> getPendingSyncActions();
  Future<void> deleteSyncAction(String actionId);
  Future<void> close();
}
