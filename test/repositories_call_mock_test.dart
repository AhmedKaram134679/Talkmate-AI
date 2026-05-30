import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_call_repository.dart';

void main() {
  group('MockCallRepository', () {
    final repo = MockCallRepository.instance;

    test('createCall and watchById / watchUserCalls', () async {
      final call = await repo.createCall(
          senderId: 'u1', receiverId: 'u2', isVideo: true);
      expect(call.id, isNotEmpty);
      expect(call.type, CallType.video);

      final watch = await repo.watchById(call.id).first;
      expect(watch?.id, call.id);

      final list = await repo.watchUserCalls('u1').first;
      expect(list.any((c) => c.id == call.id), true);
    });

    test('updateStatus transitions to ongoing then ended', () async {
      final call = await repo.createCall(senderId: 'u3', receiverId: 'u4');
      await repo.updateStatus(call.id, CallStatus.ongoing);
      var current = await repo.watchById(call.id).first;
      expect(current?.status, CallStatus.ongoing);

      await repo.updateStatus(call.id, CallStatus.ended);
      current = await repo.watchById(call.id).first;
      expect(current?.status, CallStatus.ended);
      expect(current?.endedAt != null, true);
    });

    test('updateStatus to missed sets endedAt and appears in user streams',
        () async {
      final call = await repo.createCall(senderId: 'u5', receiverId: 'u6');
      await repo.updateStatus(call.id, CallStatus.missed);
      final current = await repo.watchById(call.id).first;
      expect(current?.status, CallStatus.missed);
      expect(current?.endedAt != null, true);

      final listCaller = await repo.watchUserCalls('u5').first;
      final listCallee = await repo.watchUserCalls('u6').first;
      expect(listCaller.any((c) => c.id == call.id), true);
      expect(listCallee.any((c) => c.id == call.id), true);
    });

    test('updateStatus to rejected sets endedAt', () async {
      final call = await repo.createCall(senderId: 'u7', receiverId: 'u8');
      await repo.updateStatus(call.id, CallStatus.rejected);
      final current = await repo.watchById(call.id).first;
      expect(current?.status, CallStatus.rejected);
      expect(current?.endedAt != null, true);
    });
  });
}
