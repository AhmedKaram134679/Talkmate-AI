import 'package:talkmate_ai/data/models/typing_indicator_model.dart';

abstract class ITypingRepository {
  Future<void> startTyping(String chatId, String userId);
  Future<void> updateTyping(String chatId, String userId);
  Future<void> stopTyping(String chatId, String userId);
  Stream<List<TypingIndicator>> watchTyping(String chatId);
  Future<void> clearAllTypingForUser(String userId);
  Future<void> close();
}
