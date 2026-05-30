import 'package:talkmate_ai/data/models/message_model.dart';

/// Abstraction for message persistence and streams
abstract class IMessageRepository {
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
  });

  Stream<List<Message>> watchChatMessages(String chatId, {int limit = 100});

  Future<void> updateStatus(
    String chatId,
    String messageId,
    MessageStatus status,
  );

  Future<void> markChatAsRead(String chatId);

  Future<void> addReaction(
      String chatId, String messageId, String userId, String emoji);
  Future<void> removeReaction(
      String chatId, String messageId, String userId, String emoji);
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  });
  Future<void> editMessageText(String chatId, String messageId, String newText);
  Future<void> deleteMessageForMe(
      {required String chatId,
      required String messageId,
      required String userId});
  Future<void> softDeleteForAll(
      {required String chatId,
      required String messageId,
      required String deletedByName});
  Future<void> close();
}
