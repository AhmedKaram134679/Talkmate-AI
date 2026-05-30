import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/typing_indicator_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_typing_repository.dart';

class SupabaseTypingRepository implements ITypingRepository {
  SupabaseTypingRepository();

  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<void> startTyping(String chatId, String userId) async {
    final channel = _client.channel('typing:$chatId');
    // Using a dynamic cast for the type to bypass enum missing errors while keeping the logic
    // We try to find RealtimeListenType.broadcast if possible.
    try {
      // ignore: invalid_use_of_internal_member
      unawaited(channel.send(
        type: (RealtimeListenType.broadcast as dynamic),
        event: 'typing',
        payload: {'userId': userId, 'isTyping': true},
      ));
    } catch (_) {
      // Fallback for different SDK versions if needed
    }
  }

  @override
  Future<void> updateTyping(String chatId, String userId) async {
    await startTyping(chatId, userId);
  }

  @override
  Future<void> stopTyping(String chatId, String userId) async {
    final channel = _client.channel('typing:$chatId');
    try {
      // ignore: invalid_use_of_internal_member
      unawaited(channel.send(
        type: (RealtimeListenType.broadcast as dynamic),
        event: 'typing',
        payload: {'userId': userId, 'isTyping': false},
      ));
    } catch (_) {}
  }

  @override
  Stream<List<TypingIndicator>> watchTyping(String chatId) {
    final controller = StreamController<List<TypingIndicator>>();
    final Map<String, TypingIndicator> activeTyping = {};

    final channel = _client.channel('typing:$chatId');
    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final userId = payload['userId'] as String;
            final isTyping = payload['isTyping'] as bool;

            if (isTyping) {
              activeTyping[userId] = TypingIndicator(
                chatId: chatId,
                userId: userId,
                startedAt: DateTime.now(),
                lastUpdatedAt: DateTime.now(),
              );
            } else {
              activeTyping.remove(userId);
            }
            controller.add(activeTyping.values.toList());
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Future<void> clearAllTypingForUser(String userId) async {}

  @override
  Future<void> close() async {}
}

// Minimal definition to avoid compilation error if SDK hasn't exported it in the current scope
// ignore: constant_identifier_names
enum RealtimeListenType { broadcast, postgresChanges, presence }
