import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/friend_request_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friend_request_repository.dart';

class SupabaseFriendRequestRepository implements IFriendRequestRepository {
  SupabaseFriendRequestRepository();

  final _client = Supabase.instance.client;

  @override
  Future<void> sendRequest(
      {required String fromUserId, required String toUserId}) async {
    await _client.from('friend_requests').insert({
      'sender_id': fromUserId,
      'receiver_id': toUserId,
      'status': FriendRequestStatus.pending.name,
    });
  }

  @override
  Stream<List<FriendRequestModel>> watchIncoming(String userId) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .map((list) {
          if (list.isNotEmpty) {
            debugPrint('Incoming friend requests raw: $list');
          }
          return list
              .map((item) =>
                  FriendRequestModel.fromJson(item, item['id'].toString()))
              .toList();
        });
  }

  @override
  Stream<List<FriendRequestModel>> watchOutgoing(String userId) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('sender_id', userId)
        .map((list) => list
            .map((item) =>
                FriendRequestModel.fromJson(item, item['id'].toString()))
            .toList());
  }

  @override
  Future<void> accept(String requestId) async {
    await _client.from('friend_requests').update({
      'status': FriendRequestStatus.accepted.name,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }

  @override
  Future<void> decline(String requestId) async {
    await _client.from('friend_requests').update({
      'status': FriendRequestStatus.declined.name,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }

  @override
  Future<void> cancel(String requestId) async {
    await _client.from('friend_requests').update({
      'status': FriendRequestStatus.canceled.name,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }
}
