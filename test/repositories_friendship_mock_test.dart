import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_friendship_repository.dart';

void main() {
  group('MockFriendshipRepository', () {
    final repo = MockFriendshipRepository.instance;

    test('createFriendship and areFriends', () async {
      await repo.createFriendship(userA: 'a', userB: 'b');
      final friendsList = await repo.getAllForUser('a');
      expect(friendsList, contains('b'));
      final areTheyFriends = await repo.areFriends('a', 'b');
      expect(areTheyFriends, true);
    });

    test('watchAllForUser emits list containing friendship', () async {
      await repo.createFriendship(userA: 'x', userB: 'y');
      final stream = repo.watchAllForUser('x');
      final initial = await stream.first;
      expect(initial, contains('y'));
    });
  });
}
