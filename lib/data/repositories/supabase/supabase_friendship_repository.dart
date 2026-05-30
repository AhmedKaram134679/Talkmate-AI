import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';

class SupabaseFriendshipRepository implements IFriendshipRepository {
  SupabaseFriendshipRepository();

  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<void> sendFriendRequest(String fromId, String toId) async {
    await _client.from('friends').insert({
      'user_id': fromId,
      'friend_id': toId,
      'status': 'pending',
    });
  }

  @override
  Future<void> acceptFriendRequest(String userId, String friendId) async {
    await _client.from('friends').update({
      'status': 'accepted',
    }).or(
        'and(user_id.eq.$userId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$userId)');
  }

  @override
  Future<void> rejectFriendRequest(String userId, String friendId) async {
    await _client.from('friends').delete().or(
        'and(user_id.eq.$userId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$userId)');
  }

  @override
  Stream<List<String>> watchFriends(String userId) {
    return _client
        .from('friends')
        .stream(primaryKey: ['user_id', 'friend_id'])
        .eq('status', 'accepted')
        .map((data) {
          final friends = <String>[];
          for (final row in data) {
            if (row['user_id'] == userId) {
              friends.add(row['friend_id']);
            } else if (row['friend_id'] == userId) {
              friends.add(row['user_id']);
            }
          }
          return friends;
        });
  }

  @override
  Future<void> createFriendship(
      {required String userA, required String userB}) async {
    await sendFriendRequest(userA, userB);
    await acceptFriendRequest(userA, userB);
  }

  @override
  Future<bool> areFriends(String userId, String friendId) async {
    final res = await _client
        .from('friends')
        .select()
        .eq('status', 'accepted')
        .or('and(user_id.eq.$userId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$userId)')
        .maybeSingle();
    return res != null;
  }

  @override
  Future<List<String>> getAllForUser(String userId) async {
    final res = await _client
        .from('friends')
        .select()
        .eq('status', 'accepted')
        .or('user_id.eq.$userId,friend_id.eq.$userId');

    final friends = <String>[];
    for (final row in (res as List)) {
      final rowMap = row as Map<String, dynamic>;
      if (rowMap['user_id'] == userId) {
        friends.add(rowMap['friend_id'] as String);
      } else {
        friends.add(rowMap['user_id'] as String);
      }
    }
    return friends;
  }

  @override
  Stream<List<String>> watchAllForUser(String userId) => watchFriends(userId);

  @override
  Future<void> deleteFriendship(String userId, String friendId) async {
    await rejectFriendRequest(userId, friendId);
  }

  @override
  Future<void> close() async {}
}
