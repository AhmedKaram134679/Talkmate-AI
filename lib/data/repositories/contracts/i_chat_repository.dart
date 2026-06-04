import 'package:talkmate_ai/data/models/chat_model.dart';
import 'package:talkmate_ai/data/models/message_model.dart';

abstract class IChatRepository {
  Future<Chat> createChat({
    required List<String> participantIds,
    bool isGroup = false,
    String? groupName,
    String? groupPhotoUrl,
  });

  Future<Chat?> getById(String chatId);

  Stream<Chat?> watchById(String chatId);

  Stream<List<Chat>> watchUserChats(String userId);

  // بديل بدون ترتيب لتجاوز الحاجة إلى فهرس مركب
  Stream<List<Chat>> watchUserChatsNoOrder(String userId);

  Future<void> updateLastMessage({
    required String chatId,
    required Message message,
  });

  Future<void> removeUserFromChat({
    required String chatId,
    required String userId,
  });

  Future<void> updateGroupMeta({
    required String chatId,
    String? name,
    String? description,
    String? photoUrl,
  });

  Future<void> addUsersToChat({
    required String chatId,
    required List<String> userIds,
  });

  Future<void> updateParticipantSettings({
    required String chatId,
    required String userId,
    bool? isPinned,
    bool? isMuted,
    DateTime? muteUntil,
    bool? isArchived,
  });
  Future<void> close();
}
