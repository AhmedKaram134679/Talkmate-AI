import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_block_repository.dart';

class SupabaseBlockRepository implements IBlockRepository {
  SupabaseBlockRepository();

  final _client = Supabase.instance.client;

  @override
  Future<void> block(
      {required String blockerId, required String blockedId}) async {
    await _client.from('blocked_users').insert({
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  @override
  Future<void> unblock(
      {required String blockerId, required String blockedId}) async {
    await _client.from('blocked_users').delete().match({
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  @override
  Stream<List<String>> watchBlockedIds(String userId) {
    return _client
        .from('blocked_users')
        .stream(primaryKey: ['blocker_id', 'blocked_id'])
        .eq('blocker_id', userId)
        .map((list) =>
            list.map((item) => item['blocked_id'] as String).toList());
  }
}
