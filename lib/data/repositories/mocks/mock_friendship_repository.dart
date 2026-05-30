import 'dart:async';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';

class MockFriendshipRepository implements IFriendshipRepository {
  MockFriendshipRepository._();
  static final MockFriendshipRepository instance = MockFriendshipRepository._();

  final Set<String> _friendships = {}; // format "userId1:userId2"
  final Map<String, StreamController<List<String>>> _controllers = {};

  StreamController<List<String>> _getController(String userId) {
    // ignore: close_sinks
    return _controllers.putIfAbsent(
        userId, () => StreamController<List<String>>.broadcast());
  }

  String _key(String a, String b) {
    final list = [a, b]..sort();
    return list.join(':');
  }

  @override
  Future<void> sendFriendRequest(String fromId, String toId) async {
    _friendships.add(_key(fromId, toId));
  }

  @override
  Future<void> acceptFriendRequest(String userId, String friendId) async {
    _friendships.add(_key(userId, friendId));
  }

  @override
  Future<void> rejectFriendRequest(String userId, String friendId) async {
    _friendships.remove(_key(userId, friendId));
  }

  @override
  Stream<List<String>> watchFriends(String userId) {
    // ignore: close_sinks
    final controller = _getController(userId);
    void emit() {
      if (controller.isClosed) return;
      final list = _friendships
          .where((k) => k.contains(userId))
          .map((k) => k.split(':').firstWhere((id) => id != userId))
          .toList();
      controller.add(list);
    }

    Future.microtask(emit);
    return controller.stream;
  }

  @override
  Future<void> createFriendship(
      {required String userA, required String userB}) async {
    _friendships.add(_key(userA, userB));
  }

  @override
  Future<bool> areFriends(String userId, String friendId) async {
    return _friendships.contains(_key(userId, friendId));
  }

  @override
  Future<List<String>> getAllForUser(String userId) async {
    return _friendships
        .where((k) => k.contains(userId))
        .map((k) => k.split(':').firstWhere((id) => id != userId))
        .toList();
  }

  @override
  Stream<List<String>> watchAllForUser(String userId) => watchFriends(userId);

  @override
  Future<void> deleteFriendship(String userId, String friendId) async {
    _friendships.remove(_key(userId, friendId));
  }

  @override
  Future<void> close() async {
    for (final ctrl in _controllers.values) {
      await ctrl.close();
    }
    _controllers.clear();
  }
}
