import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/data/models/call_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_call_repository.dart';

import '_common_it.dart';

void main() {
  group('IT: CallRepository (Supabase)', () {
    test('create/watch/updateStatus/watchUserCalls', () async {
      if (!ItEnv.enabled) {
        debugPrint('Skipping integration test - TALKMATE_IT not set');
        return;
      }

      final ready = await ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('Skipping integration test - Supabase not available');
        return;
      }

      final repo = SupabaseCallRepository();
      Get.put<ICallRepository>(repo);

      final caller = 'it_caller_${Random().nextInt(1 << 32)}';
      final callee = 'it_callee_${Random().nextInt(1 << 32)}';

      final call = await repo.createCall(
        senderId: caller,
        receiverId: callee,
        isVideo: true,
      );
      expect(call.id, isNotEmpty);
      expect(call.type, CallType.video);
      expect(call.status, CallStatus.ringing);

      final watched = await repo.watchById(call.id).first;
      expect(watched?.id, call.id);

      await repo.updateStatus(call.id, CallStatus.ongoing);
      final updated = await repo.watchById(call.id).first;
      expect(updated?.status, CallStatus.ongoing);

      final callerCalls = await repo.watchUserCalls(caller).first;
      expect(callerCalls.any((c) => c.id == call.id), true);

      final calleeCalls = await repo.watchUserCalls(callee).first;
      expect(calleeCalls.any((c) => c.id == call.id), true);

      await repo.updateStatus(call.id, CallStatus.ended);
      final ended = await repo.watchById(call.id).first;
      expect(ended?.status, CallStatus.ended);
    });
  });
}
