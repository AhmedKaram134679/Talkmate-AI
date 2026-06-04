import 'package:talkmate_ai/data/models/friend_request_model.dart';

abstract class IFriendRequestRepository {
  Future<void> sendRequest(
      {required String fromUserId, required String toUserId});
  Stream<List<FriendRequestModel>> watchIncoming(String userId);
  Stream<List<FriendRequestModel>> watchOutgoing(String userId);
  Future<void> accept(String requestId);
  Future<void> decline(String requestId);
  Future<void> cancel(String requestId);
}
