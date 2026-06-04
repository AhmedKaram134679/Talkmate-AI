abstract class IBlockRepository {
  Future<void> block({required String blockerId, required String blockedId});
  Future<void> unblock({required String blockerId, required String blockedId});
  Stream<List<String>> watchBlockedIds(String userId);
}
