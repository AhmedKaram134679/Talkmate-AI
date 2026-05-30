abstract class IFriendshipRepository {
  Future<void> sendFriendRequest(String fromId, String toId);
  Future<void> acceptFriendRequest(String userId, String friendId);
  Future<void> rejectFriendRequest(String userId, String friendId);
  Stream<List<String>> watchFriends(String userId);

  // Added back for UI compatibility / simple friendship management
  Future<void> createFriendship({required String userA, required String userB});
  Future<bool> areFriends(String userId, String friendId);
  Future<List<String>> getAllForUser(String userId);
  Stream<List<String>> watchAllForUser(String userId);

  // For UI cleanup convenience
  Future<void> deleteFriendship(String userId, String friendId);
  Future<void> close();
}
