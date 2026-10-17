import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/data/models/typing_indicator_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_typing_repository.dart';

class SupabaseTypingRepository implements ITypingRepository {
  SupabaseTypingRepository();

  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, RealtimeChannel> _activeChannels = {};
  final Map<String, StreamController<List<TypingIndicator>>> _controllers = {};
  final Map<String, Map<String, TypingIndicator>> _activeTypingPerChat = {};
  final Map<String, Map<String, Timer>> _typingTimeoutsPerChat = {};

  static const Duration _typingTimeout = Duration(seconds: 4);

  RealtimeChannel _getOrCreateChannel(String chatId) {
    if (!_activeChannels.containsKey(chatId)) {
      final channel = _client.channel('typing:$chatId');
      _activeChannels[chatId] = channel;
      channel.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('⚠️ [SupabaseTypingRepository] Channel error for typing:$chatId: $error');
        }
      });
    }
    return _activeChannels[chatId]!;
  }

  @override
  Future<void> startTyping(String chatId, String userId) async {
    try {
      final channel = _getOrCreateChannel(chatId);
      // ignore: invalid_use_of_protected_member
      (channel as dynamic).send(
        type: 'broadcast',
        event: 'typing',
        payload: {'userId': userId, 'isTyping': true, 'chatId': chatId},
      );
    } catch (e) {
      debugPrint('⚠️ [SupabaseTypingRepository] startTyping error: $e');
    }
  }

  @override
  Future<void> updateTyping(String chatId, String userId) async {
    await startTyping(chatId, userId);
  }

  @override
  Future<void> stopTyping(String chatId, String userId) async {
    try {
      final channel = _getOrCreateChannel(chatId);
      // ignore: invalid_use_of_protected_member
      (channel as dynamic).send(
        type: 'broadcast',
        event: 'typing',
        payload: {'userId': userId, 'isTyping': false, 'chatId': chatId},
      );
    } catch (e) {
      debugPrint('⚠️ [SupabaseTypingRepository] stopTyping error: $e');
    }
  }

  @override
  Stream<List<TypingIndicator>> watchTyping(String chatId) {
    if (_controllers.containsKey(chatId) && !_controllers[chatId]!.isClosed) {
      return _controllers[chatId]!.stream;
    }

    // ignore: close_sinks
    final controller = StreamController<List<TypingIndicator>>.broadcast();
    _controllers[chatId] = controller;
    _activeTypingPerChat[chatId] ??= {};
    _typingTimeoutsPerChat[chatId] ??= {};

    final channel = _getOrCreateChannel(chatId);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (controller.isClosed) return;
        final userId = payload['userId']?.toString();
        final isTyping = payload['isTyping'] == true;

        if (userId == null || userId.isEmpty) return;

        final activeMap = _activeTypingPerChat[chatId] ??= {};
        final timeoutMap = _typingTimeoutsPerChat[chatId] ??= {};

        timeoutMap[userId]?.cancel();

        if (isTyping) {
          activeMap[userId] = TypingIndicator(
            chatId: chatId,
            userId: userId,
            startedAt: DateTime.now(),
            lastUpdatedAt: DateTime.now(),
          );

          // [Stage B7]: Automatic timeout cleanup
          timeoutMap[userId] = Timer(_typingTimeout, () {
            if (!controller.isClosed) {
              activeMap.remove(userId);
              controller.add(activeMap.values.toList());
            }
          });
        } else {
          activeMap.remove(userId);
          timeoutMap.remove(userId);
        }

        if (!controller.isClosed) {
          controller.add(activeMap.values.toList());
        }
      },
    );

    controller.onCancel = () {
      // Keep channel alive if other listeners attach, or clean if no listeners remain
      if (!controller.hasListener) {
        _cleanupChatTyping(chatId);
      }
    };

    return controller.stream;
  }

  void _cleanupChatTyping(String chatId) {
    _typingTimeoutsPerChat[chatId]?.forEach((_, timer) => timer.cancel());
    _typingTimeoutsPerChat.remove(chatId);
    _activeTypingPerChat.remove(chatId);
    _activeChannels[chatId]?.unsubscribe();
    _activeChannels.remove(chatId);
    final ctrl = _controllers.remove(chatId);
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.close();
    }
  }

  @override
  Future<void> clearAllTypingForUser(String userId) async {
    for (final chatId in _activeChannels.keys.toList()) {
      await stopTyping(chatId, userId);
      final activeMap = _activeTypingPerChat[chatId];
      if (activeMap != null && activeMap.containsKey(userId)) {
        activeMap.remove(userId);
        _typingTimeoutsPerChat[chatId]?[userId]?.cancel();
        _typingTimeoutsPerChat[chatId]?.remove(userId);
        if (_controllers[chatId]?.isClosed == false) {
          _controllers[chatId]?.add(activeMap.values.toList());
        }
      }
    }
  }

  @override
  Future<void> close() async {
    for (final chatId in _activeChannels.keys.toList()) {
      _cleanupChatTyping(chatId);
    }
  }
}
